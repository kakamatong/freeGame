local skynet = require "skynet"
local log = require "log"
local CMD = {}
local dbSvr = nil
local crypt = require "skynet.crypt"
local cjson = require "cjson"
require "skynet.manager"
local function start()
    dbSvr = skynet.localname(CONFIG.SVR_NAME.DB)
end

local function pushLog(userid, nickname, ip, loginType, status, ext)
	skynet.send(dbSvr, "lua", "dbLog", "insertAuthLog", userid, nickname, ip, loginType, status, ext)
end

local function check(userid, token)
    local key = string.format("user:%d", userid)
    local info = skynet.call(dbSvr, "lua", "dbRedis", "hgetall", key)
    if info and info[2] and info[4] then
        --return true
        local secret = crypt.hexdecode(info[2])
        local newToken = crypt.base64decode(token)
        local strdata = crypt.desdecode(secret, newToken)
        if not strdata then
            log.warn("auth check fail, userid %d, token %s svrToken %s svrSubid %d", userid, token, info[2], info[4])
            return false
        end

        local data = cjson.decode(strdata)
        if data and data.subid == tonumber(info[4]) then
            return data
        else
            log.warn("auth check fail, userid %d, token %s svrToken %s svrSubid %d", userid, token, info[2], info[4])
        return false
        end
    else
        log.warn("auth check fail, userid %d, token %s svrToken %s svrSubid %d", userid, token, info[2], info[4])
        return false
    end
end

local function addSubid(userid, clientSubid)
    local key = string.format("user:%d", userid)
    skynet.call(dbSvr, "lua", "dbRedis", "hset", key, "subid", tonumber(clientSubid) + 1)
end

function CMD.auth(data)
    if not data.userid or not data.token then
        return false
    end
    local userid = data.userid
    local token = data.token
    local ip = data.ip
    local status = 0
    local uri = data.uri
    local loginData = check(userid, token)
    if loginData then
        status = 1
        addSubid(userid, loginData.subid)
        pushLog(userid, "", ip, loginData.channel, status, uri)
        return true
    else
        log.warn("auth fail, userid %d, token %s", userid, token)
        pushLog(userid, "", ip, "", status, uri)
        return false
    end
    
end

function CMD.authGame(data)
    if not data.userid or not data.token then
        return false
    end
    local userid = data.userid
    local token = data.token
    local loginData = check(userid, token)
    if loginData then
        addSubid(userid, loginData.subid)
        --pushLog(userid, "", ip, loginType, status, uri)
        return true
    else
        log.warn("auth fail, userid %d, token %s", userid, token)
        --pushLog(userid, "", ip, loginType, status, uri)
        return false
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)
    skynet.register(CONFIG.SVR_NAME.AUTH)
    start()
end)