local skynet = require "skynet"
local log = require "log"
local cluster = require "skynet.cluster"
require "skynet.manager"
local cjson = require "cjson"
local CMD = {}
local upTime = 60 * 2
local key = "clusterConfig"
local clusterConfigVer = 0
local list = {}
local list2 = {}

-- 新增全局变量
local svrNodes = {}
local svrServices = {}
local bopen = false

local function createGateSvr()
	-- 启动协议加载服务（用于sproto协议）
	skynet.newservice("protoloader")
	local data = {
		address = skynet.getenv("gateAddress"),
    	port = skynet.getenv("gatePort"),
    	maxclient = skynet.getenv("gateMaxclient"),
	}
	-- 启动网关服务
	local svr = skynet.newservice("wsWatchdog")
	skynet.call(svr, "lua", "start", data)
	local gate = skynet.localname(CONFIG.SVR_NAME.GATE)
	cluster.register(CONFIG.CLUSTER_SVR_NAME.GATE, gate)
end

local function createGameSvr()
	local svr = skynet.newservice("wsGameGate")
	local data = {
		address = skynet.getenv("gateAddress"),
    	port = skynet.getenv("gatePort"),
    	maxclient = skynet.getenv("gateMaxclient"),
	}
	skynet.call(svr, "lua", "open", data)
	local svrGame = skynet.newservice("games/server")
	cluster.register(CONFIG.CLUSTER_SVR_NAME.GAME, svrGame)
end

local function createCommonSvr(path, name)
	local svr = skynet.newservice(path)
	if name then
		cluster.register(name, svr)
	end
end

local function createSvr()
    local nodeName = skynet.getenv("clusterName")
    local serviceType = nil
    local nodeInfo = nil
    
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
    
    -- 根据服务类型创建对应数量的服务
    log.info("Creating %d services of type %s on node %s", nodeInfo.cnt, serviceType, nodeName)
    
    -- 根据服务类型选择不同的创建函数
    if serviceType == "gate" then-- gate只会创建一个
        -- 启动协议加载服务（用于sproto协议）
        createGateSvr()
    elseif serviceType == "game" then-- game只会创建一个
        createGameSvr()
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
        
        for i = 1, nodeInfo.cnt do
            local serviceName = string.format("%s%d", serviceType, i)
            createCommonSvr(servicePath, serviceName)
        end
    end

    if not bopen then
        cluster.open(nodeName)
        bopen = true
    end
end

local function dealList(data)
    local list = {}
    svrNodes = {}
    svrServices = {}
    
    for key, value in pairs(data) do
        list[key] = {}
        svrNodes[key] = {}
        
        for k, v in ipairs(value) do
            local name = v.name
            local addr = v.addr
            local cnt = v.cnt
            
            -- 保存节点信息
            table.insert(svrNodes[key], { name = name, addr = addr, cnt = cnt })
            
            -- 保存服务信息
            svrServices[name] = svrServices[name] or {}
            for i = 1, cnt do
                local serviceName = string.format("%s%d", name, i)
                list[serviceName] = addr
                table.insert(svrServices[name], serviceName)
            end
        end
    end
    return list
end

local function checkClusterConfigUp()
    local svrDB = skynet.localname(CONFIG.SVR_NAME.DB)
    local strClusterConfig = skynet.call(svrDB, "lua", "dbRedis", "get", key)
    log.info("strClusterConfig: %s", strClusterConfig)
    local config = cjson.decode(strClusterConfig)
    if config.ver ~= clusterConfigVer then
        cluster.reload({["__nowaiting"] = true})
        clusterConfigVer = config.ver
        list = config.list
        local clusterConfig = dealList(list)
        log.info("clusterConfig: %s", UTILS.tableToString(clusterConfig))
        cluster.reload(clusterConfig)
    end
end

-- "{"ver":1,"list":{"lobby":"127.0.0.1:13006","match":"127.0.0.1:13001","robot":"127.0.0.1:13007","gate":"127.0.0.1:13005","game":"127.0.0.1:13002","login":"127.0.0.1:13004"}}"
function CMD.start()
    checkClusterConfigUp()
    skynet.fork(function()
        while true do
            -- 从redis获取clusterConfig
            skynet.sleep(upTime * 100)
            checkClusterConfigUp()
        end
    end)
end

function CMD.checkHaveSvr(name)
    return svrNodes[name]
end

function CMD.call(svrName, funcName, ...)
    local nodes = svrNodes[svrName]
    if not nodes or #nodes <= 0 then
        log.info("call fail svrName: %s", svrName)
        return nil
    end
    
    -- 随机选择一个节点
    local nodeIndex = math.random(1, #nodes)
    local node = nodes[nodeIndex]
    
    -- 随机选择该节点上的一个服务
    local services = svrServices[node.name]
    if not services or #services <= 0 then
        log.info("call fail no services on node: %s", node.name)
        return nil
    end
    
    local serviceIndex = math.random(1, #services)
    local serviceName = services[serviceIndex]
    
    return cluster.call(node.name, "@" .. serviceName, funcName, ...)
end

function CMD.callTo(node, svrName, funcName, ...)
    return cluster.call(node, "@" .. svrName, funcName, ...)
end

function CMD.send(svrName, funcName, ...)
    local nodes = svrNodes[svrName]
    if not nodes or #nodes <= 0 then
        log.info("send fail svrName: %s", svrName)
        return nil
    end
    
    -- 随机选择一个节点
    local nodeIndex = math.random(1, #nodes)
    local node = nodes[nodeIndex]
    
    -- 随机选择该节点上的一个服务
    local services = svrServices[node.name]
    if not services or #services <= 0 then
        log.info("send fail no services on node: %s", node.name)
        return nil
    end
    
    local serviceIndex = math.random(1, #services)
    local serviceName = services[serviceIndex]
    
    return cluster.send(node.name, "@" .. serviceName, funcName, ...)
end

function CMD.sendTo(node, svrName, funcName, ...)
    return cluster.send(node, "@" .. svrName, funcName, ...)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    skynet.register(CONFIG.SVR_NAME.CLUSTER)
end)