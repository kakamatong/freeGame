local skynet = require "skynet"
local log = require "log"
local cluster = require "skynet.cluster"
local cjson = require "cjson"
local CMD = {}
local upTime = 60 * 2
local key = "clusterConfig"
local clusterConfigVer = 0

function CMD.start()
    skynet.fork(function()
        while true do
            skynet.sleep(upTime * 10)
            -- 从redis获取clusterConfig
            local svrDB = skynet.localname(CONFIG.SVR_NAME.DB)
            local strClusterConfig = skynet.call(svrDB, "lua", "dbRedis", "get", key)
            local config = cjson.decode(strClusterConfig)
            if config.ver ~= clusterConfigVer then
                clusterConfigVer = config.ver
                cluster.reload(config.list)
            end
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