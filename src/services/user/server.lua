local skynet = require "skynet"
local log = require "log"
local CMD = {}
local dbSvr = nil
-- 返回结果
-- 获取数据库服务句柄

local function start()
    dbSvr = skynet.uniqueservice(CONFIG.SVR_NAME.DB)
end

function CMD.userData(userid)
    log.info("userData userid %d", userid)
	local userData = skynet.call(dbSvr, "lua", "db", "getUserData", userid)
	assert(userData)
	return userData
end

function CMD.userRiches(userid, args)
	local userRiches = skynet.call(dbSvr, "lua", "db", "getUserRiches", userid)
	if not userRiches then
		return {}, {}
	end
	local richType = {}
	local richNums = {}
	for k,v in pairs(userRiches) do
		table.insert(richType, v.richType)
		table.insert(richNums, v.richNums)
	end

	return richType, richNums
end

function CMD.userStatus(userid)
	local status = skynet.call(dbSvr, "lua", "db", "getUserStatus", userid)
    assert(status)
	return status.status, status.gameid ,status.roomid
end

function CMD.setUserStatus(userid, status, gameid, roomid)  
    assert(userid)
    assert(status)
	skynet.send(dbSvr, "lua", "db", "setUserStatus", userid, status, gameid, roomid)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)
    start()
end)