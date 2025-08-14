local tools = {}
local skynet = require "skynet"
local cjson = require "cjson"
local log = require "log"
local svrDB = nil
local svrUser = CONFIG.CLUSTER_SVR_NAME.USER

local function getDB()
    if not svrDB then
        svrDB = skynet.localname(CONFIG.SVR_NAME.DB)
    end
    return svrDB
end

function tools.result(info)
    if info then
        if type(info) == "table" or type(info) == "number" then
            return {code = 1, result = cjson.encode(info)}
        else
            return {code = 1, result = info}
        end
    else
        return {code = 0, result = "调用接口失败"}
    end
end

-- 调用redis
function tools.callRedis(func,...)
    return skynet.call(getDB(), "lua", "dbRedis", func, ...)
end

-- 调用mysql
function tools.callMysql(func,...)
    return skynet.call(getDB(), "lua", "db", func, ...)
end

function tools.userData(userid)
    return call(svrUser, "userData", userid)
end

return tools