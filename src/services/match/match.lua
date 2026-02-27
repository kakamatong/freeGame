local skynet = require "skynet"
local log = require "log"
local gConfig = CONFIG
local match = {}
local queueUserids = {}
local inMatchList = {}
local btest = false
local svrGame = CONFIG.CLUSTER_SVR_NAME.GAME
local svrRobot = CONFIG.CLUSTER_SVR_NAME.ROBOT
local svrUser = CONFIG.CLUSTER_SVR_NAME.USER
local matchOnSure = require("match.matchOnSure")
local matchConfig = require("match.matchConfig")
local svrDB = nil

local function getDB()
    if not svrDB then
        svrDB = skynet.localname(CONFIG.SVR_NAME.DB)
    end
    return svrDB
end

local function setUserStatus(userid, status, gameid, roomid, addr)
    send(svrUser , "setUserStatus", userid, status, gameid, roomid, addr, 0)
end

local function getUserStatus(userid)
    local status = call(svrUser, "userStatus", userid)
    return status
end

local function checkInGame(tmpGameid, tmpRoomid)
	local b = call(svrGame, "checkHaveRoom", tmpGameid, tmpRoomid)
	if not b then
		log.error("game not found %d %d", tmpGameid, tmpRoomid)
		return
	end

	return true
end

local function checkGame(gameid, queueid)
    local gameConfig = matchConfig.games[gameid]
    if not gameConfig then
        return false
    end

    if queueid > gameConfig.queueNum then
        return false
    end

    return true
end

-- 玩家进入匹配队列
local function enterQueue(userid, gameid, queueid, cp)
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
    cp = cp or 0
    local index = 1
    for i, v in ipairs(queueUserids[gameid][queueid]) do
        if cp > v.rate then
            index = i
            break
        end
    end
    table.insert(queueUserids[gameid][queueid], index, {userid = userid, rate = cp, checkNum = 0})
    inMatchList[userid] = true
    setUserStatus(userid, gConfig.USER_STATUS.MATCHING, 0, 0, "")
    return true
end

-- 匹配成功
local function matchSuccess(gameid, queueid, user1, user2)
    log.info("matchSuccess %d %d", user1.userid, user2.userid)
    local playerids = {user1.userid, user2.userid}
    matchOnSure.startOnSure(gameid, queueid, playerids, {rule = "", rate = {user1.rate, user2.rate}})
end

-- 匹配成功，与机器人匹配
local function matchSuccessWithRobot(gameid, queueid, user, robotData)
    log.info("matchWithRobot %d %s", user.userid, UTILS.tableToString(robotData))
    local playerids = {user.userid, robotData.userid}
    matchOnSure.startOnSure(gameid, queueid, playerids, {rule = "", robots = {robotData.userid}, rate = {user.rate, robotData.cp}})
end

local function getRobots(gameid, num)
    local robot = call(svrRobot, "getRobots", gameid, num)
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
    matchOnSure.startOnSure(gameid, queueid, playerids, {rule = "", robots = playerids})
end

-- 检查用户匹配失败次数，如果次数过多，则直接与机器人匹配（固定模式）
local function checkMatchNum(gameid, queueid, user, config)
    if user.checkNum >= config.robotAfterFails then
        local robot = getRobots(gameid, 1)
        if robot and #robot > 0 then
            matchSuccessWithRobot(gameid, queueid, user, robot[1])
            return true
        end
    end
    return false
end

-- 动态匹配成功
local function matchSuccessDynamic(gameid, queueid, users, config)
    local playerids = {}
    local rates = {}
    local robots = {}
    
    for _, user in ipairs(users) do
        table.insert(playerids, user.userid)
        table.insert(rates, user.rate)
        inMatchList[user.userid] = nil
        if user.isRobot then
            table.insert(robots, user.userid)
        end
    end
    
    log.info("dynamic match success gameid=%d queueid=%d players=%d", gameid, queueid, #playerids)
    matchOnSure.startOnSure(gameid, queueid, playerids, {
        rule = "",
        rate = rates,
        robots = #robots > 0 and robots or nil
    })
end

-- 动态模式下检查是否需要机器人
local function checkNeedRobotDynamic(gameid, queueid, waitingUsers, config)
    if not config or not waitingUsers or #waitingUsers == 0 then
        return false
    end
    
    -- 检查是否有人超过最大等待次数
    local needRobot = false
    for _, user in ipairs(waitingUsers) do
        if user.checkNum >= config.robotAfterFails then
            needRobot = true
            break
        end
    end
    
    if needRobot then
        local robotNum = config.maxPlayers - #waitingUsers
        if robotNum > 0 then
            local robots = getRobots(gameid, robotNum)
            if robots and #robots >= robotNum then
                -- 合并用户和机器人
                for _, robot in ipairs(robots) do
                    table.insert(waitingUsers, {
                        userid = robot.userid,
                        rate = robot.cp,
                        isRobot = true
                    })
                end
                matchSuccessDynamic(gameid, queueid, waitingUsers, config)
                return true
            end
        end
    end
    return false
end

-- 固定人数匹配
local function checkQueueFixed(gameid, queueid, config)
    local que = queueUserids[gameid][queueid]
    local queLen = #que
    local i = 1
    local rateDiff = config.rateDiff
    
    while i <= queLen do
        if i < queLen then
            local user1 = que[i]
            local user2 = que[i+1]
            if math.abs(user1.rate - user2.rate) < rateDiff then
                log.info("fixed match success %d %d", user1.userid, user2.userid)
                table.remove(que, i)
                table.remove(que, i)
                inMatchList[user1.userid] = nil
                inMatchList[user2.userid] = nil
                i = i - 1
                queLen = queLen - 2
                matchSuccess(gameid, queueid, user1, user2)
            else
                user1.checkNum = user1.checkNum + 1
                -- 如果用户匹配失败次数过多，则直接与机器人匹配
                if checkMatchNum(gameid, queueid, user1, config) then
                    table.remove(que, i)
                    inMatchList[user1.userid] = nil
                    i = i - 1
                    queLen = queLen - 1
                end
            end
        else
            local user = que[i]
            user.checkNum = user.checkNum + 1
            if checkMatchNum(gameid, queueid, user, config) then
                table.remove(que, i)
                inMatchList[user.userid] = nil
            end
        end
        i = i + 1
    end
end

-- 动态人数匹配
local function checkQueueDynamic(gameid, queueid, config)
    local que = queueUserids[gameid][queueid]
    
    -- 检查是否有人超时需要机器人（即使只有1人）
    if #que > 0 and #que < config.minPlayers then
        -- 先增加所有用户的checkNum
        for _, user in ipairs(que) do
            user.checkNum = user.checkNum + 1
        end
        
        -- 检查等待中的用户是否有人超时
        local waitingUsers = {}
        for _, user in ipairs(que) do
            if user.checkNum >= config.robotAfterFails then
                table.insert(waitingUsers, user)
            end
        end
        
        -- 如果有人超时，尝试用机器人补充
        if #waitingUsers > 0 then
            if checkNeedRobotDynamic(gameid, queueid, waitingUsers, config) then
                -- 从队列中移除已匹配的用户
                for _, matchedUser in ipairs(waitingUsers) do
                    if not matchedUser.isRobot then
                        for i, quser in ipairs(que) do
                            if quser.userid == matchedUser.userid then
                                table.remove(que, i)
                                break
                            end
                        end
                    end
                end
            end
        end
        
        -- 如果队列人数仍然不足minPlayers，继续等待
        if #que < config.minPlayers then
            return
        end
    end
    
    -- 如果队列为空，直接返回
    if #que == 0 then
        return
    end
    
    local matchedGroup = {}
    local rateDiff = config.rateDiff
    local queCopy = {}
    
    -- 复制队列（因为会修改原队列）
    for _, u in ipairs(que) do
        table.insert(queCopy, u)
    end
    
    -- 清空原队列，重新填充未匹配的用户
    queueUserids[gameid][queueid] = {}
    
    -- 从队首开始构建匹配组
    while #queCopy > 0 do
        local user = table.remove(queCopy, 1)
        user.checkNum = user.checkNum + 1
        table.insert(matchedGroup, user)
        
        -- 找战力相近的用户加入组
        local i = 1
        while i <= #queCopy and #matchedGroup < config.maxPlayers do
            if math.abs(user.rate - queCopy[i].rate) < rateDiff then
                local matched = table.remove(queCopy, i)
                matched.checkNum = matched.checkNum + 1
                table.insert(matchedGroup, matched)
            else
                i = i + 1
            end
        end
        
        -- 达到最大人数，立即匹配成功
        if #matchedGroup >= config.maxPlayers then
            matchSuccessDynamic(gameid, queueid, matchedGroup, config)
            matchedGroup = {}
        end
    end
    
    -- 遍历结束，检查是否满足最小人数
    if #matchedGroup >= config.minPlayers then
        matchSuccessDynamic(gameid, queueid, matchedGroup, config)
    else
        -- 不满足，放回队列
        for _, u in ipairs(matchedGroup) do
            table.insert(queueUserids[gameid][queueid], u)
        end
        -- 检查是否需要机器人补充
        checkNeedRobotDynamic(gameid, queueid, matchedGroup, config)
    end
end

-- 检查队列，尝试匹配
local function checkQueue(gameid, queueid)
    if btest then
        testRobotPlay(gameid, queueid)
        return
    end
    
    local config = matchConfig.get(gameid, queueid)
    
    if config.mode == "fixed" then
        checkQueueFixed(gameid, queueid, config)
    else
        checkQueueDynamic(gameid, queueid, config)
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
            inMatchList[userid] = false
            return true
        end
    end
    return false
end

local function join(userid, gameid, queueid, cp)
    if inMatchList[userid] then
        return {code = 0, msg = "已经在匹配队列中"}
    end

    -- 检查用户是否在匹配队列中
    if not enterQueue(userid, gameid, queueid, cp) then
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

function match.join(userid, gameid, queueid)
    local rices = skynet.call(getDB(), "lua", "db", "getUserRichesByType", userid, CONFIG.RICH_TYPE.COMBAT_POWER)
    local cp = 0
    if rices then
        cp = rices.richNums
    end
    return join(userid, gameid, queueid, cp)
end

function match.leave(userid, gameid, queueid)
    return leave(userid, gameid, queueid)
end

function match.onSure(userid, id, sure)
    return matchOnSure.onSure(userid, id, sure)
end

function match.tick()
    matching()
    matchOnSure.checkOnSure()
end

return match


