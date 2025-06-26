local tools = {}
local skynet = require "skynet"
local cjson = require "cjson"

function tools.result(info)
    local msg = {}
    if info then
        msg = info
    end
    return {code = 1, result = cjson.encode(msg)}
end

function tools.getDB()
    local dbserver = skynet.localname(".dbserver")
	assert(dbserver, "dbserver not started")
	return dbserver
end

function tools.callRedis(func,...)
    local db = tools.getDB()
    return skynet.call(db, "lua", "funcRedis", func, ...)
end

function tools.callMysql(func,...)
    local db = tools.getDB()
    return skynet.call(db, "lua", "func", func, ...)
end

return tools