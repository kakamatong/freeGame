local skynet = require "skynet"
local log = require "log"
local CMD = {}
local defaultModule = "user"
local path = "user."
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

local function start()
    
end

local function userData(userid, args)
    log.info("userData userid %d", userid)
	local db = getDB()
	local userData = skynet.call(db, "lua", "db", "getUserData", userid)
	assert(userData)

	return userData
end

local function userRiches(userid, args)
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

local function userStatus(userid, args)
	local db = getDB()
	local status = skynet.call(db, "lua", "db", "getUserStatus", userid)
	if not status then
		return {gameid = 0 , status = -1}
	else
		return {gameid = status.gameid , status=status.status, roomid = status.roomid}
	end
end

local function setUserStatus(userid, args)  
	local status = args.status
	local gameid = args.gameid
	local roomid = args.roomid
	if not status then return end
	local db = getDB()
	skynet.send(db, "lua", "db", "setUserStatus", userid, status, gameid, roomid)
end

-----------------------------------------------------------------------------------------------
local clent = {}
-- 获取用户详细数据
function clent.userData(userid, args)
	return userData(userid, args)
end

-- 获取用户财富信息
function clent.userRiches(userid, args)
	return userRiches(userid, args)
end

-- 获取用户状态
function clent.userStatus(userid, args)
	return userStatus(userid, args)
end
------------------------------------------------------------------------------------------------
local svr = {}
function svr.userData(userid, args)
	return userData(userid, args)
end

-- 获取用户财富信息
function svr.userRiches(userid, args)
	return userRiches(userid, args)
end

-- 获取用户状态
function svr.userStatus(userid, args)
	return userStatus(userid, args)
end

-- 设置用户状态到数据库
function svr.setUserStatus(userid, args)  
	setUserStatus(userid, args)
end

-----------------------------------------------------------------------------------------------
function CMD.svrCall(moduleName, funcName, userid, args)
    local func = assert(svr[funcName])
    return func(userid, args)
end

function CMD.clientCall(moduleName, funcName, userid, args)
    local func = clent[funcName]
    if not func then
        return UTILS.result()
    end
    return func(userid, args)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)
    start()
end)