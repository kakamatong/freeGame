local skynet = require "skynet"
local log = require "log"

local auth = {}

function auth.auth(data)
    if not data.userid or not data.token or not data.subid then
        return false
    end
    local userid = data.userid
    local token = data.token
    local clientSubid = data.subid
    local dbserver = skynet.localname(".db")
    if not dbserver then
        return false
    end
    local key = string.format("user:%d", userid)
    local info = skynet.call(dbserver, "lua", "dbRedis", "hgetall", key)
    log.info(UTILS.tableToString(info))
    if info and info[2] == token and info[4] == clientSubid then
        skynet.call(dbserver, "lua", "dbRedis", "hset", key, "subid", tonumber(clientSubid) + 1)
        return true
    else
        log.warn("auth fail, userid %d, token %s, clientSubid %s", userid, token, clientSubid)
    end

    return false
end

return auth