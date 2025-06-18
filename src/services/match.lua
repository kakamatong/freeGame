-- match.lua
-- 匹配服务，负责玩家匹配逻辑和队列管理
local skynet = require "skynet"
require "skynet.manager"
local CMD = {}
local name = "match"
local users = {}         -- 记录所有正在匹配的用户信息
local queueNum = 4       -- 匹配队列数量
local queueUserids = {}  -- queueUserids[gameid][queueid] = {userid1, ...}
local dTime = 1          -- 匹配检查间隔（秒）
local CHECK_MAX_NUM = 5       -- 匹配检查次数

local function checkGame(gameid, queueid)
    local gameConfig = CONFIG.MATCH_GAMES[gameid]
    if not gameConfig then
        return false
    end

    if queueid > gameConfig.queueNum then
        return false
    end

    return true
end

-- 匹配成功后通知agent
local function reportToAgent(userid,gamedata)
    local user = users[userid]
    local agent = user.agent
    -- 通知agent进入游戏
    skynet.send(agent, "lua", "enterGame", gamedata)
end

-- 离开队列
local function leaveQueue(userid)
    LOG.info("leaveQueue %d", userid)
    if not users[userid] then
        return false
    end
    local gameid = users[userid].gameid
    local queueid = users[userid].queueid
    local queue = queueUserids[gameid][queueid]
    LOG.info("queueUserids start %s", UTILS.tableToString(queue))
    if not queueUserids[gameid] or not queue then
        return false
    end 
    for i, v in ipairs(queue) do
        if v == userid then
            table.remove(queue, i)
            break
        end
    end
    users[userid] = nil
    LOG.info("queueUserids end %s", UTILS.tableToString(queue))
    return true
end

-- 创建游戏
local function createGame(gameid, playerids, gameData)
    local gameManager = skynet.localname(".gameManager")
    local roomid = skynet.call(gameManager, "lua", "createGame", gameid, playerids, gameData)
    return roomid
end

-- 匹配成功
local function matchSuccess(userid1, userid2)
    -- 1.创建游戏
    -- 2.通知agent
    -- 3.删除queue里的用户
    local playerids = {userid1, userid2}
    local gameid = users[userid1].gameid
    local roomid = createGame(gameid, playerids, {rule = ""})
    local gameData = {gameid = gameid, roomid = roomid}
    reportToAgent(userid1, gameData)
    reportToAgent(userid2, gameData)
    
    leaveQueue(userid1)
    leaveQueue(userid2)
end

local function matchWithRobot(userid, robotData)
    LOG.info("matchWithRobot %d %s", userid, UTILS.tableToString(robotData))
    local playerids = {userid, robotData.userid}
    local gameid = users[userid].gameid
    local roomid = createGame(gameid, playerids, {rule = "", robots = {robotData.userid}})
    local gameData = {gameid = gameid, roomid = roomid}
    -- 通知机器人进入游戏
    local robotManager = skynet.localname(".robotManager")
    if not robotManager then
        return nil
    end
    skynet.send(robotManager, "lua", "robotEnter", gameid, roomid, robotData.userid)

    reportToAgent(userid, gameData)
    
    leaveQueue(userid)
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
local function checkMatchNum(gameid,userid)
    LOG.info("checkMatchNum %d", userid)
    local user = users[userid]
    if user and user.checkNum >= CHECK_MAX_NUM then
        LOG.info("checkMatchNum %d %d", userid, user.checkNum)
        local robot = getRobots(gameid, 1)
        if robot and #robot > 0 then
            user.matchSuccess = true
            matchWithRobot(userid, robot[1])
        end
    end
end

-- 检查队列，尝试匹配
local function checkQueue(gameid, queueid)
    --LOG.info("checkQueue %d %d", gameid, queueid)
    local que = queueUserids[gameid][queueid]
    --LOG.info("que %s", UTILS.tableToString(que))
    for i = 1, #que do
        if i < #que then
            local userid1 = que[i]
            local userid2 = que[i+1]
            local user1 = users[userid1]
            local user2 = users[userid2]
            if not user1 or not user2 then
                break
            end
            if user1.matchSuccess or user2.matchSuccess then
                break
            end
            if math.abs(user1.rate - user2.rate) < 0.05 then
                LOG.info("match success %d %d", userid1, userid2)
                user1.matchSuccess = true
                user2.matchSuccess = true
                matchSuccess(userid1, userid2)
            else
                user1.checkNum = user1.checkNum + 1
                if i == #que - 1 then
                    user2.checkNum = user2.checkNum + 1
                end

                -- 如果用户匹配失败次数过多，则直接与机器人匹配
                checkMatchNum(gameid, userid1)
                checkMatchNum(gameid, userid2)
                
            end
        else
            local userid1 = que[i]
            local user1 = users[userid1]
            if not user1 then
                break
            end
            if user1.matchSuccess then
                break
            end
            user1.checkNum = user1.checkNum + 1
            checkMatchNum(gameid, userid1)
        end
    end
end

-- 启动匹配服务，定时检查所有队列
function CMD.start()
    LOG.info("match start")
    skynet.fork(function()
        while true do
            for gameid, queues in pairs(queueUserids) do
                for queueid, que in pairs(queues) do
                    checkQueue(gameid, queueid)
                end
            end
            skynet.sleep(dTime * 100)
        end
    end)
end

-- 停止匹配服务
function CMD.stop()
    LOG.info("match stop")
end

-- 玩家进入匹配队列
function CMD.enterQueue(agent, userid, gameid, queueid, rate)
    LOG.info("enterQueue %d %d %d", userid, gameid, queueid)
    if not gameid or not queueid or queueid == 0 then
        return false
    end
    
    if not checkGame(gameid, queueid) then
        return false
    end

    if not users[userid] then
        users[userid] = {
            userid = userid,
            gameid = gameid,
            queueid = queueid or 0,
            rate = rate or 0,
            agent = agent,
            checkNum = 0,
            matchSuccess = false,
            time = os.time(),
        }
    else
        return false
    end

    if not queueUserids[gameid] then
        queueUserids[gameid] = {}
    end
    if not queueUserids[gameid][queueid] then
        queueUserids[gameid][queueid] = {}
    end
    --根据rate的大小插入队列
    local index = 1
    for i, v in ipairs(queueUserids[gameid][queueid]) do
        if rate > users[v].rate then
            index = i
            break
        end
    end
    table.insert(queueUserids[gameid][queueid], index, userid)
    return true
end

-- 玩家离开匹配队列
function CMD.leaveQueue(userid)
    return leaveQueue(userid)
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		--skynet.trace()
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
    skynet.register("." .. name)
end)