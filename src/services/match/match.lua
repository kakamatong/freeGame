local skynet = require "skynet"
local log = require "log"
local gConfig = CONFIG
local match = {}
local queueUserids = {}
local inMatchList = {}
local CHECK_MAX_NUM = 5
local btest = false

local function setUserStatus(userid, status, gameid, roomid)
    local svrUser = skynet.localname(".user")
    if not svrUser then
        return
    end
    local data = {
        status = status,
        gameid = gameid,
        roomid = roomid,
    }
    send(svrUser , "user", "setUserStatus", userid, data)
end

local function getUserStatus(userid)
    local svrUser = skynet.localname(".user")
    if not svrUser then
        return
    end
    local status = call(svrUser, "user", "userStatus", userid)
    return status
end

local function checkInGame(tmpGameid, tmpRoomid)
	local gameServer = skynet.localname(".game")
	if not gameServer then
		log.error("game not started")
		return
	end
    local data = {
        gameid = tmpGameid,
        roomid = tmpRoomid,
    }

	local b = call(gameServer, "game", "checkHaveRoom", data)
	if not b then
		log.error("game not found %d %d", tmpGameid, tmpRoomid)
		return
	end

	return true
end

local function checkGame(gameid, queueid)
    local gameConfig = gConfig.MATCH_GAMES[gameid]
    if not gameConfig then
        return false
    end

    if queueid > gameConfig.queueNum then
        return false
    end

    return true
end

-- 玩家进入匹配队列
local function enterQueue(userid, gameid, queueid, rate)
    log.info("enterQueue %d %d %d", userid, gameid, queueid)
    if not gameid or not queueid or queueid == 0 then
        return false
    end

    if inMatchList[userid] then
        return false
    end
    
    if not checkGame(gameid, queueid) then
        return false
    end

    if not queueUserids[gameid] then
        queueUserids[gameid] = {}
    end
    if not queueUserids[gameid][queueid] then
        queueUserids[gameid][queueid] = {}
    end
    --根据rate的大小插入队列
    rate = rate or 0
    local index = 1
    for i, v in ipairs(queueUserids[gameid][queueid]) do
        if rate > v.rate then
            index = i
            break
        end
    end
    table.insert(queueUserids[gameid][queueid], index, {userid = userid, rate = rate, checkNum = 0})
    inMatchList[userid] = true
    setUserStatus(userid, gConfig.USER_STATUS.MATCHING, 0, 0)
    return true
end

-- 匹配成功
local function matchSuccess(gameid, queueid, userid1, userid2)
    log.info("matchSuccess %d %d", userid1, userid2)
    local playerids = {userid1, userid2}

    local matchOnSure = require("match.matchOnSure")
    matchOnSure.startOnSure(gameid, queueid, playerids, {rule = ""})
end

-- 匹配成功，与机器人匹配
local function matchSuccessWithRobot(gameid, queueid, userid, robotData)
    log.info("matchWithRobot %d %s", userid, UTILS.tableToString(robotData))
    local playerids = {userid, robotData.userid}
    local matchOnSure = require("match.matchOnSure")
    matchOnSure.startOnSure(gameid, queueid, playerids, {rule = "", robots = {robotData.userid}})
end

local function getRobots(gameid, num)
    local robot = skynet.localname(".robot")
    if not robot then
        return nil
    end
    local data = {
        gameid = gameid,
        num = num,
    }
    local robot = call(robot, "robot", "getRobots", data)
    return robot
end

local function testRobotPlay(gameid, queueid)
    log.info("testRobotPlay %d %d", gameid, queueid)
    local robot = getRobots(gameid, 2)
    if not robot or not robot[1] or not robot[2] then
        log.info("not enough robot")
        return
    end
    local playerids = {robot[1].userid, robot[2].userid}
    local matchOnSure = require("match.matchOnSure")
    matchOnSure.startOnSure(gameid, queueid, playerids, {rule = "", robots = playerids})
end

-- 检查用户匹配失败次数，如果次数过多，则直接与机器人匹配
local function checkMatchNum(gameid, queueid, userid, checkNum)
    --log.info("checkMatchNum %d", userid)
    if checkNum >= CHECK_MAX_NUM then
        --log.info("checkMatchNum %d %d", userid, checkNum)
        local robot = getRobots(gameid, 1)
        if robot and #robot > 0 then
            matchSuccessWithRobot(gameid, queueid, userid, robot[1])
            return true
        end
    end
end

-- 检查队列，尝试匹配
local function checkQueue(gameid, queueid)
    if btest then
        testRobotPlay(gameid, queueid)
        --return
    end
    --log.info("checkQueue %d %d", gameid, queueid)
    local que = queueUserids[gameid][queueid]
    --log.info("que %s", UTILS.tableToString(que))
    local queLen = #que
    local i = 1
    while i <= queLen do
        if i < queLen then
            local user1 = que[i]
            local user2 = que[i+1]
            if math.abs(user1.rate - user2.rate) < 0.05 then
                log.info("match success %d %d", user1.userid, user2.userid)
                table.remove(que, i)
                table.remove(que, i)
                inMatchList[user1.userid] = nil
                inMatchList[user2.userid] = nil
                i = i - 1
                queLen = queLen - 2
                matchSuccess(gameid, queueid, user1.userid, user2.userid)
            else
                user1.checkNum = user1.checkNum + 1
                -- 如果用户匹配失败次数过多，则直接与机器人匹配
                if checkMatchNum(gameid, queueid, user1.userid, user1.checkNum) then
                    table.remove(que, i)
                    inMatchList[user1.userid] = nil
                    i = i - 1
                    queLen = queLen - 1
                end
            end
        else
            local user = que[i]
            user.checkNum = user.checkNum + 1
            if checkMatchNum(gameid, queueid, user.userid, user.checkNum) then
                table.remove(que, i)
                inMatchList[user.userid] = nil
            end
        end
        i = i + 1
    end
end

local function leaveQueue(userid, gameid, queueid)
    if not queueUserids[gameid] then
        return false
    end

    local que = queueUserids[gameid][queueid]
    if not que then
        return false
    end
    for i, v in ipairs(que) do
        if v.userid == userid then
            table.remove(que, i)
            return true
        end
    end
    return false
end

local function join(userid, gameid, queueid)
    if inMatchList[userid] then
        return {code = 0, msg = "已经在匹配队列中"}
    end

    -- todo: 检查用户是否在游戏中
    local status = getUserStatus(userid)
    if status and status.gameid > 0 and status.roomid > 0 then
        if checkInGame(status.gameid, status.roomid) then
            return {code = 0, msg = "已经在游戏中", gameid = status.gameid, roomid = status.roomid}
        end
    end

    -- 检查用户是否在匹配队列中
    if not enterQueue(userid, gameid, queueid) then
        return {code = 0, msg = "加入匹配队列失败"}
    end
    return {code = 1, msg = "加入匹配队列成功"}
end

local function matching()
    for gameid, queues in pairs(queueUserids) do
        for queueid, que in pairs(queues) do
            checkQueue(gameid, queueid)
        end
    end
end

local function leave(userid, gameid, queueid)
    if not leaveQueue(userid, gameid, queueid) then
        return {code = 0, msg = "离开匹配队列失败"}
    end
    return {code = 1, msg = "离开匹配队列成功"}
end

function match.startTest()
    btest = true
    return {code = 1, msg = "开启测试模式成功"}
end

function match.stopTest()
    btest = false
    return {code = 1, msg = "关闭测试模式成功"}
end

function match.join(userid, args)
    local gameid = args.gameid
    local queueid = args.queueid
    return join(userid, gameid, queueid)
end

function match.leave(userid, args)
    local gameid = args.gameid
    local queueid = args.queueid
    return leave(userid, gameid, queueid)
end

function match.onSure(userid, args)
    local id = args.id
    local sure = args.sure
    local matchOnSure = require("match.matchOnSure")
    return matchOnSure.onSure(userid, id, sure)
end

function match.tick()
    matching()
    local matchOnSure = require("match.matchOnSure")
    matchOnSure.checkOnSure()
end

return match


