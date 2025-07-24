local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local user = {}
-- 返回结果
-- 获取数据库服务句柄
local function getDB()
	local dbserver = skynet.uniqueservice(CONFIG.SVR_NAME.DB)
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end
	return dbserver
end

-- 获取用户详细数据
function user.userData(userid, args)
	log.info("userData userid %d", userid)
	local db = getDB()
	local userData = skynet.call(db, "lua", "db", "getUserData", userid)
	assert(userData)

	return userData
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

	return {richType = richType, richNums = richNums}
end

-- 获取用户状态
function user.userStatus(userid, args)
	local db = getDB()
	local status = skynet.call(db, "lua", "db", "getUserStatus", userid)
	if not status then
		return {gameid = 0 , status = -1}
	else
		return {gameid = status.gameid , status=status.status, roomid = status.roomid}
	end
end

-- 设置用户状态到数据库
function user.setUserStatus(userid, args)
	local status = args.status
	local gameid = args.gameid
	local roomid = args.roomid
	if not status then return end
	local db = getDB()
	skynet.send(db, "lua", "db", "setUserStatus", userid, status, gameid, roomid)
end

return user