local skynet = require "skynet"
local log = require "log"

local function pushLog(userid, nickname, ip, loginType, status, ext)
	local dbserver = skynet.localname(".db")
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end
	skynet.send(dbserver, "lua", "dbLog", "insertAuthLog", userid, nickname, ip, loginType, status, ext)
end

local function check(userid, token, clientSubid)
    local dbserver = skynet.localname(".db")
    if not dbserver then
        return false
    end
    local key = string.format("user:%d", userid)
    local info = skynet.call(dbserver, "lua", "dbRedis", "hgetall", key)
    if info and info[2] == token and info[4] == clientSubid then
        return true
    else
        return false
    end
end

local function addSubid(userid, clientSubid)
    local dbserver = skynet.localname(".db")
    if not dbserver then
        return
    end
    local key = string.format("user:%d", userid)
    skynet.call(dbserver, "lua", "dbRedis", "hset", key, "subid", tonumber(clientSubid) + 1)
end

local auth = {}
function auth.auth(data)
    if not data.userid or not data.token or not data.subid then
        return false
    end
    local userid = data.userid
    local token = data.token
    local clientSubid = data.subid
    local loginType = data.channel
    local ip = data.ip
    local status = 0
    local uri = data.uri

    if check(userid, token, clientSubid) then
        status = 1
        addSubid(userid, clientSubid)
        return true
    else
        log.warn("auth fail, userid %d, token %s, clientSubid %s", userid, token, clientSubid)
    end
    pushLog(userid, "", ip, loginType, status, uri)
    return false
end

return auth