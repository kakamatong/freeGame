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
local proxys = {}
local configs = {}

local function checkConfig()
    for k,v in pairs(list) do
        local name = UTILS.string_split(k, "#")
        configs[name[1]] = configs[name[1]] or {}
        table.insert(configs[name[1]], v)
        local proxyName = k .. "@" .. name[1]
        log.info("proxyName: %s", proxyName)
        local ok,proxy = pcall(cluster.query, k, name[1])
        if ok then
            proxys[name[1]] = proxys[name[1]] or {}
            table.insert(proxys[name[1]], proxy)
        end
    end
    log.info(UTILS.tableToString(configs))
end

local function checkClusterConfigUp()
    local svrDB = skynet.localname(CONFIG.SVR_NAME.DB)
    local strClusterConfig = skynet.call(svrDB, "lua", "dbRedis", "get", key)
    log.info("strClusterConfig: %s", strClusterConfig)
    local config = cjson.decode(strClusterConfig)
    if config.ver ~= clusterConfigVer then
        clusterConfigVer = config.ver
        list = config.list
        config.list["__nowaiting"] = false 
        cluster.reload(config.list)
        --checkConfig()
    end
end

-- "{"ver":1,"list":{"lobby":"127.0.0.1:13006","match":"127.0.0.1:13001","robot":"127.0.0.1:13007","gate":"127.0.0.1:13005","game":"127.0.0.1:13002","login":"127.0.0.1:13004"}}"
function CMD.start()
    checkClusterConfigUp()
    skynet.fork(function()
        while true do
            -- 从redis获取clusterConfig
            skynet.sleep(upTime * 10)
            checkClusterConfigUp()
        end
    end)
end

function CMD.call(svrName, funcName, ...)
    
end

function CMD.send(svrName, funcName, ...)
    
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)
    skynet.register(CONFIG.SVR_NAME.CLUSTER)
end)