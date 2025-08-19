--[[
集群管理服务
负责管理游戏服务端集群的节点和服务，包括：
1. 集群节点的注册与发现
2. 服务的创建与管理
3. 集群配置的动态更新
4. 跨节点服务调用的负载均衡
]]
local skynet = require "skynet"         -- 引入skynet框架
local log = require "log"               -- 引入日志模块
local cluster = require "skynet.cluster" -- 引入集群通信模块
require "skynet.manager"                -- 引入服务管理模块
local cjson = require "cjson"           -- 引入JSON解析模块
local CMD = {}                           -- 定义命令表，用于处理外部调用
local upTime = 60 * 2                    -- 配置检查间隔时间(秒)
local key = "clusterConfig"             -- Redis中存储集群配置的键名
local clusterConfigVer = 0               -- 当前集群配置版本
local list = {}                          -- 集群节点列表
local list2 = {}                         -- 集群节点列表副本

-- 新增全局变量
local svrNodes = {}                      -- 按服务类型分类的节点信息
local svrServices = {}                   -- 节点上的服务信息
local bopen = false                      -- 集群是否已开启
-- 添加一个全局变量来跟踪每种类型服务的创建数量
local createdServicesCount = {}          -- 每种服务类型的创建计数
local nodeIndexs = {}                    -- 节点索引，用于负载均衡
local svrIndexs = {}                     -- 服务索引，用于负载均衡
local indexUpTime = 0.1                  -- 索引更新时间间隔(秒),更小的时间间隔，更平均的负载均衡（如果瞬间负载压力过大，可以改小这个值）

--[[
创建网关服务
负责启动协议加载服务和网关服务，并注册到集群
@return 网关服务句柄
]]
local function createGateSvr()
	-- 启动协议加载服务（用于sproto协议）
	skynet.newservice("protoloader")
	local data = {
		address = skynet.getenv("gateAddress"), -- 网关地址
    	port = skynet.getenv("gatePort"),       -- 网关端口
    	maxclient = skynet.getenv("gateMaxclient") -- 最大客户端连接数
	}
	-- 启动网关服务
	local svr = skynet.newservice("wsWatchdog")
	skynet.call(svr, "lua", "start", data)
	local gate = skynet.localname(CONFIG.SVR_NAME.GATE)
	cluster.register("gate1", gate)  -- 注册网关服务到集群
    return gate
end

--[[
创建游戏服务
负责启动游戏网关和游戏服务，并注册到集群
@return 游戏服务句柄
]]
local function createGameSvr()
	local svr = skynet.newservice("wsGameGate")
	local data = {
		address = skynet.getenv("gateAddress"),
    	port = skynet.getenv("gatePort"),
    	maxclient = skynet.getenv("gateMaxclient"),
	}
	skynet.call(svr, "lua", "open", data)
	local svrGame = skynet.newservice("games/server")
	cluster.register("game1", svrGame)  -- 注册游戏服务到集群
	return svrGame
end

--[[
创建Web服务
负责启动Web服务，并注册到集群
@return Web服务句柄
]]
local function createWebSvr()
	local svr = skynet.newservice("web/server")
	local port = skynet.getenv("port")
	skynet.call(svr, "lua", "open", port)
	cluster.register("web1", svr)  -- 注册Web服务到集群
	return svr
end

--[[
创建通用服务
@param path 服务路径
@param name 服务名称(可选)
@return 服务句柄
]]
local function createCommonSvr(path, name)
	local svr = skynet.newservice(path)
	if name then
		cluster.register(name, svr)  -- 注册服务到集群
	end
    return svr
end

--[[
创建服务
根据当前节点类型和配置创建相应的服务
]]
local function createSvr()
    local nodeName = skynet.getenv("clusterName") -- 当前节点名称
    local serviceType = nil                       -- 服务类型
    local nodeInfo = nil                          -- 节点信息
    
    -- 查找节点名称对应的服务类型
    for type, nodes in pairs(svrNodes) do
        for _, node in ipairs(nodes) do
            if node.name == nodeName then
                serviceType = type
                nodeInfo = node
                break
            end
        end
        if serviceType then
            break
        end
    end
    
    if not serviceType or not nodeInfo then
        log.error("Cannot find service type for node: %s", nodeName)
        return
    end
    
    -- 初始化该类型服务的创建计数（如果不存在）
    createdServicesCount[serviceType] = createdServicesCount[serviceType] or 0
    
    -- 检查是否已经创建足够的服务
    if createdServicesCount[serviceType] >= nodeInfo.cnt then
        log.info("Already created enough services of type %s on node %s", serviceType, nodeName)
        return
    end
    
    -- 计算需要补充创建的服务数量
    local needCreateCount = nodeInfo.cnt - createdServicesCount[serviceType]
    log.info("Need to create %d more services of type %s on node %s", needCreateCount, serviceType, nodeName)
    
    -- 根据服务类型选择不同的创建函数
    if serviceType == "gate" then-- gate只会创建一个
        if createdServicesCount[serviceType] == 0 then
            createGateSvr()
            createdServicesCount[serviceType] = 1
        end
    elseif serviceType == "game" then-- game只会创建一个
        if createdServicesCount[serviceType] == 0 then
            createGameSvr()
            createdServicesCount[serviceType] = 1
        end
    elseif serviceType == "web" then-- web只会创建一个
        if createdServicesCount[serviceType] == 0 then
            createWebSvr()
            createdServicesCount[serviceType] = 1
        end
    else
        -- 对于其他类型的服务，使用通用创建函数
        local servicePathMap = {
            match = "match/server",
            robot = "robot/server",
            login = "wsLogind",
            user = "user/server",
            activity = "activity/server",
            auth = "auth/server"
            -- 可以根据需要添加更多服务类型的路径映射
        }
        
        local servicePath = servicePathMap[serviceType] or serviceType.."/server"
        
        -- 只创建需要的数量
        for i = createdServicesCount[serviceType] + 1, nodeInfo.cnt do
            local serviceName = string.format("%s%d", serviceType, i)
            createCommonSvr(servicePath, serviceName)
        end
        
        -- 更新创建计数
        createdServicesCount[serviceType] = nodeInfo.cnt
    end

    if not bopen then
        cluster.open(nodeName)  -- 开启集群通信
        bopen = true
    end
end

--[[
处理集群配置列表
@param data 集群配置数据
@return 处理后的集群配置
]]
local function dealList(data)
    local list = {}
    svrNodes = {}
    svrServices = {}
    
    for key, value in pairs(data) do
        svrNodes[key] = {}
        
        for k, v in ipairs(value) do
            local name = v.name
            local addr = v.addr
            local cnt = v.cnt
            local hide = v.hide
            
            -- 保存节点信息
            list[name] = addr
            -- 保存服务信息
            if not hide then
                table.insert(svrNodes[key], { name = name, addr = addr, cnt = cnt, hide = hide })
                svrServices[name] = svrServices[name] or {}
                for i = 1, cnt do
                    local serviceName = string.format("%s%d", key, i)
                    table.insert(svrServices[name], serviceName)
                end
            end
        end
    end
    log.info("svrNodes: %s", UTILS.tableToString(svrNodes))
    log.info("svrServices: %s", UTILS.tableToString(svrServices))
    log.info("list: %s", UTILS.tableToString(list))
    list2 = list
    return list
end

--[[
更新索引
]]
local function updateIndex()
    for svrType, nodes in pairs(svrNodes) do
        local cntNode = #nodes
        if cntNode > 1 then
            local nodeIndex = nodeIndexs[svrType]
            nodeIndexs[svrType] = (nodeIndex + 1) % (cntNode + 1)
            if nodeIndexs[svrType] == 0 then
                nodeIndexs[svrType] = 1
            end
        else
            nodeIndexs[svrType] = 1
        end

        for _, node in ipairs(nodes) do
            local nodeName = node.name
            local services = svrServices[nodeName]
            if services then
                local cntSvr = #services
                if cntSvr > 1 then
                    local svrIndex = svrIndexs[nodeName]
                    svrIndex[nodeName] = (svrIndex + 1) % (cntSvr + 1)
                    if svrIndex[nodeName] == 0 then
                        svrIndex[nodeName] = 1
                    end
                else
                    svrIndexs[nodeName] = 1
                end
            end

        end
    end
end

--[[
检查集群配置更新
从Redis获取最新配置，如果有更新则应用
]]
local function checkClusterConfigUp()
    local svrDB = skynet.localname(CONFIG.SVR_NAME.DB)  -- 获取数据库服务
    local strClusterConfig = skynet.call(svrDB, "lua", "dbRedis", "get", key)  -- 从Redis获取配置
    log.info("strClusterConfig: %s", strClusterConfig)
    local config = cjson.decode(strClusterConfig)  -- 解析JSON配置
    if config.ver ~= clusterConfigVer then
        cluster.reload({["__nowaiting"] = true})  -- 重新加载集群配置
        clusterConfigVer = config.ver
        list = config.list
        local clusterConfig = dealList(list)
        log.info("clusterConfig: %s", UTILS.tableToString(clusterConfig))
        cluster.reload(clusterConfig)
        createSvr()  -- 创建服务
        updateIndex()  -- 更新索引
    end
end

--[[
启动集群管理服务
]]
function CMD.start()
    checkClusterConfigUp()
    skynet.fork(function()
        while true do
            -- 定期检查集群配置更新
            skynet.sleep(upTime * 100)
            checkClusterConfigUp()
        end
    end)

    skynet.fork(function()
        while true do
            -- 定期更新索引
            skynet.sleep(indexUpTime * 100)
            updateIndex()
        end
    end)
end

--[[
检查节点是否存在
@param name 节点名称
@return 节点地址或nil
]]
function CMD.checkHaveNode(name)
    -- 遍历所有服务类型的节点
    return list2[name]
end

--[[
调用指定类型的服务
@param svrType 服务类型
@param funcName 函数名称
@param ... 其他参数
@return 调用结果
]]
function CMD.call(svrType, funcName, ...)
    --log.info("call svrType: %s, funcName: %s", svrType, funcName)
    local nodeIndex = nodeIndexs[svrType] or 1
    local node = svrNodes[svrType][nodeIndex]
    if not node then    
        log.info("call fail no node: %s", svrType)
        return nil
    end

    local services = svrServices[node.name]
    local cntSvr = #services
    if not services or cntSvr <= 0 then
        log.info("call fail no services on node: %s", node.name)
        return nil
    end

    local serviceIndex = svrIndexs[node.name] or 1
    local serviceName = services[serviceIndex]
    
    --log.info("call svrType: %s, funcName: %s, node: %s, serviceName: %s", svrType, funcName, node.name, serviceName)
    return cluster.call(node.name, "@" .. serviceName, funcName, ...)
end

--[[
调用指定节点上的指定服务
@param node 节点名称
@param svrName 服务名称
@param funcName 函数名称
@param ... 其他参数
@return 调用结果
]]
function CMD.callTo(node, svrName, funcName, ...)
    --log.info("callTo node: %s, svrName: %s, funcName: %s", node, svrName, funcName)
    return cluster.call(node, "@" .. svrName, funcName, ...)
end

--[[
发送消息到指定类型的服务
@param svrType 服务类型
@param funcName 函数名称
@param ... 其他参数
@return 发送结果
]]
function CMD.send(svrType, funcName, ...)
    --log.info("send svrType: %s, funcName: %s", svrType, funcName)
    local nodeIndex = nodeIndexs[svrType] or 1
    local node = svrNodes[svrType][nodeIndex]
    if not node then    
        log.info("call fail no node: %s", svrType)
        return nil
    end
    
    -- 随机选择该节点上的一个服务
    local services = svrServices[node.name]
    local cntSvr = #services
    if not services or cntSvr <= 0 then
        log.info("call fail no services on node: %s", node.name)
        return nil
    end

    local serviceIndex = svrIndexs[node.name] or 1
    local serviceName = services[serviceIndex]
    
    --log.info("send svrType: %s, funcName: %s, node: %s, serviceName: %s", svrType, funcName, node.name, serviceName)
    return cluster.send(node.name, "@" .. serviceName, funcName, ...)
end

--[[
发送消息到指定节点上的指定服务
@param node 节点名称
@param svrName 服务名称
@param funcName 函数名称
@param ... 其他参数
@return 发送结果
]]
function CMD.sendTo(node, svrName, funcName, ...)
    return cluster.send(node, "@" .. svrName, funcName, ...)
end

--[[
服务入口点
注册命令处理函数并将服务注册到Skynet
]]
skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    skynet.register(CONFIG.SVR_NAME.CLUSTER)
end)