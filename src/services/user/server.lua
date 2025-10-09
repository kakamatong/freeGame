local skynet = require "skynet"
local log = require "log"
local CMD = {}
local dbSvr = nil
require "skynet.manager"
-- 返回结果
-- 获取数据库服务句柄

local function start()
    dbSvr = skynet.localname(CONFIG.SVR_NAME.DB)
end

function CMD.userData(userid)
    log.info("userData userid %d", userid)
	local userData = skynet.call(dbSvr, "lua", "db", "getUserData", userid)
	assert(userData)
	return userData
end

function CMD.userRiches(userid)
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
	if not status then
		status = {}
		status.status = CONFIG.USER_STATUS.ONLINE
		status.gameid = 0
		status.roomid = 0
		status.shortRoomid = 0
		status.addr = ""
	end
    --assert(status)
	return status
end

function CMD.setUserStatus(userid, status, gameid, roomid, addr, shortRoomid)  
    assert(userid)
    assert(status)
	skynet.send(dbSvr, "lua", "db", "setUserStatus", userid, status, gameid, roomid, addr, shortRoomid)
end

-- 奖励通知
function CMD.awardNotice(userid,awardMessage)
    assert(userid)
    assert(awardMessage)
    return skynet.call(dbSvr, "lua", "db", "insertAwardNotice", userid, awardMessage)
end

-- 获取奖励通知
function CMD.getAwardNotice(userid,time)
    assert(userid)
    if not time then
		-- 最近30天
        time = os.date("%Y-%m-%d 00:00:00", os.time() - 30 * 24 * 60 * 60)
    end
    local res = skynet.call(dbSvr, "lua", "db", "getAwardNotice", userid, time)
    return res
end

-- 设置奖励通知为已读
function CMD.setAwardNoticeRead(id)
    assert(id)
    skynet.send(dbSvr, "lua", "db", "setAwardNoticeRead", id)
end

-- 获取用户游戏记录(输赢平)
function CMD.getUserGameRecords(userid, gameid)
	return skynet.call(dbSvr, "lua", "db", "getUserGameRecords", userid, gameid)
end

function CMD.updateUserNameAndHeadurl(userid, nickname, headurl)
    assert(userid)
    assert(nickname)
    assert(headurl)
    skynet.send(dbSvr, "lua", "db", "updateUserNameAndHeadurl", userid, nickname, headurl)
end

-- 用户申请注销账号
function CMD.revokeAcc(userid, loginType)
	assert(userid)
	local res = skynet.call(dbSvr, "lua", "db", "getRevokeAcc", userid)
	if not res then
		if skynet.call(dbSvr, "lua", "db", "applyRevokeAcc", userid,loginType) then
			return {code = 1, msg = "申请成功"}
		else
			return {code = 0, msg = "申请失败"}
		end
	else
		if res.status == 1 then
			return {code = 0, msg = "已经注销"}
		else
			local applyTime = res.applyTime
			local year, month, day, hour, min, sec = applyTime:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")

			-- 转换为时间戳
			local timestamp = os.time({
				year = tonumber(year),
				month = tonumber(month),
				day = tonumber(day),
				hour = tonumber(hour),
				min = tonumber(min),
				sec = tonumber(sec)
			})

			local timeNow = os.time()
			if timeNow - timestamp > CONFIG.REVLKE_DAY * 24 * 3600 then
				-- todo:注销
				if skynet.call(dbSvr, "lua", "db", "revokeAcc", userid) then
					skynet.send(dbSvr, "lua", "db", "delLoginInfo", userid, res.loginType)
					return {code = 3, msg = "注销成功"}
				else
					return {code = 0, msg = "注销失败"}
				end
			else
				return {code = 2, msg = "已申请"}
			end
		end
	end
end

-- 取消申请注销账号
function CMD.cancelRevokeAcc(userid)
	assert(userid)
	local res = skynet.call(dbSvr, "lua", "db", "getRevokeAcc", userid)
	if not res then
		return {code = 0, msg = "取消失败，未申请注销"}
	else
		if res.status == 1 then
			return {code = 0, msg = "已经注销"}
		end

		if skynet.call(dbSvr, "lua", "db", "delRevokeAcc", userid) then
			return {code = 1, msg = "取消成功"}
		else
			return {code = 0, msg = "取消失败"}
		end
	end
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)
    --skynet.register(CONFIG.SVR_NAME.USER)
    start()
end)