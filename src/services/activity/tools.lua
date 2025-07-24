local tools = {}
local skynet = require "skynet"
local cjson = require "cjson"
local log = require "log"
local sprotoloader = require "sprotoloader"
local host = sprotoloader.load(1):host "package"
local send_request = host:attach(sprotoloader.load(2))

local function sendSvrMsg(userid, typeName, data)
    log.info("sendSvrMsg %d %s %s", userid, typeName, cjson.encode(data))
	local pack = send_request('svrMsg', {type = typeName, data = cjson.encode(data)}, 1)
    local gate = skynet.uniqueservice(CONFIG.SVR_NAME.GATE)
    if not gate then
        return
    end
    skynet.send(gate, "lua", "sendSvrMsg", userid, pack)
end

-- 获取dbserver
function tools.getDB()
    local dbserver = skynet.uniqueservice("db/server")
	assert(dbserver, "dbserver not started")
	return dbserver
end

-- 调用redis
function tools.callRedis(func,...)
    local db = tools.getDB()
    return skynet.call(db, "lua", "dbRedis", func, ...)
end

-- 调用mysql
function tools.callMysql(func,...)
    local db = tools.getDB()
    return skynet.call(db, "lua", "db", func, ...)
end

-- 下发财富变更信息
function tools.reportAward(userid, richTypes, richNums, allRichNums)
    local data = {
        richTypes = richTypes,
        richNums = richNums,
        allRichNums = allRichNums
    }
    sendSvrMsg(userid, "updateRich", data)
end 

return tools