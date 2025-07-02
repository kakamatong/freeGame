local tools = {}
local skynet = require "skynet"
local cjson = require "cjson"

-- 返回结果
function tools.result(info)
    local msg = {}
    if info then
        msg = info
    end
    return {code = 1, result = cjson.encode(msg)}
end

-- 获取dbserver
function tools.getDB()
    local dbserver = skynet.localname(".db")
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
    return skynet.call(db, "lua", "func", func, ...)
end

-- 下发财富变更信息
function tools.reportAward(userid, richTypes, richNums)
    local gate = skynet.localname(".wsGateserver")
    assert(gate, "gate not started")
    local data = {
        type = 1,
        richTypes = richTypes,
        richNums = richNums
    }
    skynet.send(gate, "lua", "reportToAgent", userid, data)
end 

return tools