local skynet = require "skynet"
local log = require "log"
local lobby = {}
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
function lobby.userData()
	if not userData then
		local db = getDB()
		userData = skynet.call(db, "lua", "db", "getUserData", userid)
		assert(userData)
		return userData
	end
	return userData
end

-- 获取用户财富信息
function lobby.userRiches()
	local richType, richNums = getUserRiches()
	log.info("richType %s", UTILS.tableToString(richType))
	log.info("richNums %s", UTILS.tableToString(richNums))
	return {richType = richType, richNums = richNums}
end

-- 获取用户状态
function lobby.userStatus()
	local db = getDB()
	local status = skynet.call(db, "lua", "db", "getUserStatus", userid)
	if not status then
		return {gameid = 0 , status = -1}
	else
		return {gameid = status.gameid , status=status.status, roomid = status.roomid}
	end
end

return lobby