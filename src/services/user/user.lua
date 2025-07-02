local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local user = {}
-- 返回结果
-- 获取数据库服务句柄
local function getDB()
	local dbserver = skynet.localname(".db")
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end
	return dbserver
end

-- 获取用户详细数据
function user.userData(userid, args)
	if not userData then
		local db = getDB()
		userData = skynet.call(db, "lua", "db", "getUserData", userid)
		assert(userData)
		return UTILS.result(userData)
	end
	return UTILS.result(userData)
end

-- 获取用户财富信息
function user.userRiches(userid, args)
	local db = getDB()
	local userRiches = skynet.call(db, "lua", "db", "getUserRiches", userid)
	if not userRiches then
		return {}, {}
	end
	local richType = {}
	local richNums = {}
	for k,v in pairs(userRiches) do
		table.insert(richType, v.richType)
		table.insert(richNums, v.richNums)
	end

	return UTILS.result({richType = richType, richNums = richNums})
end

-- 获取用户状态
function user.userStatus(userid, args)
	local db = getDB()
	local status = skynet.call(db, "lua", "db", "getUserStatus", userid)
	if not status then
		return UTILS.result({gameid = 0 , status = -1})
	else
		return UTILS.result({gameid = status.gameid , status=status.status, roomid = status.roomid})
	end
end

return user