local skynet = require "skynet"
local log = require "log"
local CMD = {}
local dbSvr =nil
local function start()
    dbSvr = skynet.uniqueservice(CONFIG.SVR_NAME.DB)
end

local function pushLog(userid, nickname, ip, loginType, status, ext)
	skynet.send(dbSvr, "lua", "dbLog", "insertAuthLog", userid, nickname, ip, loginType, status, ext)
end

local function check(userid, token, clientSubid)
    local key = string.format("user:%d", userid)
    local info = skynet.call(dbSvr, "lua", "dbRedis", "hgetall", key)
    if info and info[2] == token and info[4] == clientSubid then
        return true
    else
        log.warn("auth check fail, userid %d, token %s, clientSubid %d svrToken %s svrSubid %d", userid, token, clientSubid, info[2], info[4])
        return false
    end
end

local function addSubid(userid, clientSubid)
    local key = string.format("user:%d", userid)
    skynet.call(dbSvr, "lua", "dbRedis", "hset", key, "subid", tonumber(clientSubid) + 1)
end

function CMD.auth(data)
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
        pushLog(userid, "", ip, loginType, status, uri)
        return true
    else
        log.warn("auth fail, userid %d, token %s, clientSubid %s", userid, token, clientSubid)
        pushLog(userid, "", ip, loginType, status, uri)
        return false
    end
    
end

function CMD.authGame(data)
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
        --pushLog(userid, "", ip, loginType, status, uri)
        return true
    else
        log.warn("auth fail, userid %d, token %s, clientSubid %s", userid, token, clientSubid)
        --pushLog(userid, "", ip, loginType, status, uri)
        return false
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)
    start()
end)