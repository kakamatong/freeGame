local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local gConfig = CONFIG
local match = {}
local queueUserids = {}
local CHECK_MAX_NUM = 5
local waitingOnSure = {}
local onSureIndex = 1

local sprotoloader = require "sprotoloader"
local host = sprotoloader.load(1):host "package"
local send_request = host:attach(sprotoloader.load(2))

local function sendSvrMsg(userid, typeName, data)
	local pack = send_request('svrMsg', {type = typeName, data = cjson.encode(data)}, 1)
    local gate = skynet.localname(".wsGateserver")
    if not gate then
        return
    end
    skynet.send(gate, "lua", "sendSvrMsg", userid, pack)
end

local function setUserStatus(userid, status, gameid, roomid)
    local svrUser = skynet.localname(".user")
    if not svrUser then
        return
    end
    skynet.send(svrUser, "lua", "svrCall" , "user", "setUserStatus", userid, status, gameid, roomid)
end

local function getUserStatus(userid)
    local svrUser = skynet.localname(".user")
    if not svrUser then
        return
    end
    local status = skynet.call(svrUser, "lua", "svrCall", "user", "userStatus", userid)
    return status
end

local function checkInGame(tmpGameid, tmpRoomid)
	local gameServer = skynet.localname(".gameManager")
	if not gameServer then
		log.error("gameManager not started")
		return
	end

	local b = skynet.call(gameServer, "lua", "checkHaveRoom", tmpGameid, tmpRoomid)
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

-- 创建游戏
local function createGame(gameid, playerids, gameData)
    local gameManager = skynet.localname(".gameManager")
    local roomid = skynet.call(gameManager, "lua", "createGame", gameid, playerids, gameData)
    return roomid
end

-- 玩家进入匹配队列
local function enterQueue(userid, gameid, queueid, rate)
    log.info("enterQueue %d %d %d", userid, gameid, queueid)
    if not gameid or not queueid or queueid == 0 then
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
    setUserStatus(userid, gConfig.USER_STATUS.MATCHING, 0, 0)
    return true
end

local function createOnSureItem(gameid, queueid, playerids, data)
    local readys = {}
    if data.robots then
        readys = data.robots
    end
    onSureIndex = onSureIndex + 1
    local item = {
        gameid = gameid,
        queueid = queueid,
        playerids = playerids,
        data = data,
        readys = readys,
        cancels = {},
        createTime = os.time(),
        id = onSureIndex
    }
    waitingOnSure[onSureIndex] = item
    return item
end

local function isRobot(userid, robots)
    for i, v in ipairs(robots) do
        if v == userid then
            return true
        end
    end
    return false
end

-- 开始超时
local function startOnSure(gameid, queueid, playerids, data)
    local item = createOnSureItem(gameid, queueid, playerids, data)
    for i, v in ipairs(playerids) do
        -- todo: 机器人
        if data.robots and isRobot(v, data.robots) then
            
        else
            sendSvrMsg(v, "matchOnSure", item)
        end
    end
end

local function onSureSuccess(item)
    local roomid = createGame(item.gameid, item.playerids, item.data)
    if roomid then
        for i, v in ipairs(item.playerids) do
            setUserStatus(v, gConfig.USER_STATUS.PLAYING, item.gameid, roomid)
            sendSvrMsg(v, "gameRoomReady", {roomid = roomid, gameid = item.gameid})
        end
    end
end

local function onSure(userid, id, sure)
    local item = waitingOnSure[id]
    if not item then
        return {code = 0, msg = "游戏不存在"}
    end
    if item.playerids[1] ~= userid then
        return {code = 0, msg = "游戏不匹配"}
    end
    if sure then
        --matchSuccess(item.gameid, item.queueid, item.playerids[1], item.playerids[2])
        table.insert(item.readys, userid)
        for i, v in ipairs(item.playerids) do
            sendSvrMsg(v, "matchOnSure", item)
        end
        if #item.readys == #item.playerids then
            --matchSuccess(item.gameid, item.queueid, item.playerids[1], item.playerids[2])
            waitingOnSure[id] = nil
            onSureSuccess(item)
        end
    else
        log.info("match fail %d", userid)
        waitingOnSure[id] = nil
        --sendSvrMsg(v, "matchOnSure", item)
        table.insert(item.cancels, userid)
        for i, v in ipairs(item.playerids) do
            if v ~= userid then
                sendSvrMsg(v, "matchOnSure", item)
            end
        end
        return {code = 1, msg = "拒绝成功"}
    end
end

-- 匹配成功
local function matchSuccess(gameid, queueid, userid1, userid2)
    log.info("matchSuccess %d %d", userid1, userid2)
    local playerids = {userid1, userid2}
    startOnSure(gameid, queueid, playerids, {rule = ""})
    --createGame(gameid, playerids, {rule = ""})
end

-- 匹配成功，与机器人匹配
local function matchSuccessWithRobot(gameid, queueid, userid, robotData)
    log.info("matchWithRobot %d %s", userid, UTILS.tableToString(robotData))
    local playerids = {userid, robotData.userid}
    startOnSure(gameid, queueid, playerids, {rule = "", robots = {robotData.userid}})
    --createGame(gameid, playerids, {rule = "", robots = {robotData.userid}})
end

local function getRobots(gameid, num)
    local robotManager = skynet.localname(".robotManager")
    if not robotManager then
        return nil
    end
    local robot = skynet.call(robotManager, "lua", "getRobots", gameid, num)
    return robot
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
    --log.info("checkQueue %d %d", gameid, queueid)
    local que = queueUserids[gameid][queueid]
    --log.info("que %s", UTILS.tableToString(que))
    local queLen = #que
    for i = 1, queLen do
        if i < queLen then
            local user1 = que[i]
            local user2 = que[i+1]
            if math.abs(user1.rate - user2.rate) < 0.05 then
                log.info("match success %d %d", user1.userid, user2.userid)
                table.remove(que, i)
                table.remove(que, i + 1)
                i = i - 1
                queLen = queLen - 2
                matchSuccess(gameid, queueid, user1.userid, user2.userid)
            else
                user1.checkNum = user1.checkNum + 1
                -- 如果用户匹配失败次数过多，则直接与机器人匹配
                if checkMatchNum(gameid, queueid, user1.userid, user1.checkNum) then
                    table.remove(que, i)
                    i = i - 1
                    queLen = queLen - 1
                end
            end
        else
            local user = que[i]
            user.checkNum = user.checkNum + 1
            if checkMatchNum(gameid, queueid, user.userid, user.checkNum) then
                table.remove(que, i)
            end
        end
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
    -- todo: 检查用户是否在游戏中
    local status = getUserStatus(userid)
    if status.gameid > 0 and status.roomid > 0 then
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
    return onSure(userid, id, sure)
end

function match.tick()
    matching()
end

return match


