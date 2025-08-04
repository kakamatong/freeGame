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

local function dealList(data)
    local list = {}
    for key, value in pairs(data) do
        for k, v in ipairs(value) do
            local name = string.format("%s%d", key, k)
            list[name] = v
        end
    end
    list2 = list
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
    return list2[name]
end

function CMD.call(svrName, funcName, ...)
    local svr = list[svrName]
    if not svr or #svr <= 0 then
        log.info("call fail svrName: %s", svrName)
        return nil
    end
    local index = math.random(1, #svr)
    local node = svrName .. tostring(index)
    return cluster.call(node, "@" .. svrName, funcName, ...)
end

function CMD.send(svrName, funcName, ...)
    local svr = list[svrName]
    if not svr or #svr <= 0  then
        log.info("send fail svrName: %s", svrName)
        return nil
    end
    local index = math.random(1, #svr)
    local node = svrName .. tostring(index)
    return cluster.send(node, "@" .. svrName, funcName, ...)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    skynet.register(CONFIG.SVR_NAME.CLUSTER)
end)