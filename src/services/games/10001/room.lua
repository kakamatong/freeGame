local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local config = require "games.10001.config"
require "skynet.manager"
local logicHandler = require "games.10001.logic"
local sprotoloader = require "sprotoloader"
local aiHandler = require "games.10001.ai"
local roomid = 0
local gameid = 0
local playerids = {} -- 玩家id列表
local gameData = {} -- 游戏数据
local players = {} -- 玩家数据
local onlines = {} -- 玩家在线状态
local client_fds = {} -- 玩家连接信息
local seats = {} -- 玩家座位信息
local canDestroy = false -- 是否可以销毁
local agents = {} -- 玩家代理
local createRoomTime = 0
local host
local gate
local gameStatus = config.GAME_STATUS.NONE
local XY = {}
local reportsessionid = 0
local gameStartTime = 0
local roomHandler = {}
local roomHandlerAi = {}
local gameManager
local send_request = nil
local dTime = 100
-- 更新玩家状态
-- 收发协议
-- 游戏逻辑
-- 销毁逻辑
-- 未开局销毁逻辑

-- 房间日志，创建，销毁，开始，结束
local function pushLog(logtype, userid, gameid, roomid, ext)
    local dbserver = skynet.localname(".dbserver")
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end

    local time = os.time()
    local timecn = os.date("%Y-%m-%d %H:%M:%S", time)
    skynet.send(dbserver, "lua", "dbLog", "insertRoomLog", logtype, userid, gameid, roomid, timecn, ext)
end

-- 游戏结果日志
local function pushLogResult(type, userid, gameid, roomid, result, score1, score2, score3, score4, score5, ext)
    local dbserver = skynet.localname(".dbserver")
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end

    local time = os.time()
    local timecn = os.date("%Y-%m-%d %H:%M:%S", time)
    skynet.send(dbserver, "lua", "dbLog", "insertResultLog", type, userid, gameid, roomid, result, score1, score2, score3, score4, score5, timecn, ext)
end

-- 用户游戏记录
local function pushUserGameRecords(userid, gameid, addType, addNums)
    local dbserver = skynet.localname(".dbserver")
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end
    skynet.send(dbserver, "lua", "db", "insertUserGameRecords", userid, gameid, addType, addNums)
end

-- 开始游戏
local function startGame()
    gameStatus = config.GAME_STATUS.START
    gameStartTime = os.time()
    logicHandler.startGame()
    pushLog(config.LOG_TYPE.GAME_START, 0, gameid, roomid, "")
    log.info("game start")
end

-- 判断是否是机器人
local function isRobotByUserid(userid)
    if gameData.robots and #gameData.robots > 0 and userid and userid > 0 then
        for _, id in pairs(gameData.robots) do
            if id == userid then
                return true
            end
        end
    end
    return false
end

-- 判断是否是机器人
local function isRobotBySeat(seat)
    local userid = seats[seat]
    return isRobotByUserid(userid)
end

-- 获取玩家座位
local function getPlayerSeat(userid)
    for i, id in pairs(seats) do
        if id == userid then
            return i
        end
    end
end

-- 测试是否可以开始游戏
local function testStart()
    log.info("testStart")
    local onlineCount = 0
    for _, playerid in pairs(playerids) do
        if onlines[playerid] ~= nil then
            onlineCount = onlineCount + 1
        else
            return false
        end
    end

    if onlineCount == #playerids then
        startGame()
        return true
    else
        return false
    end
end

-- 发送消息
local function send_package(client_fd, pack)
    skynet.send(gate, "lua", "send", client_fd, pack)
end

-- 发送消息给单个玩家
local function sendToOneClient(userid, name, data)
    if not send_request then
        return 
    end
    local client_fd = client_fds[userid]
    if client_fd and onlines[userid] then
        data.gameid = gameid
        data.roomid = roomid
        --log.info("sendToOneClient %s", UTILS.roomToString(data))
        reportsessionid = reportsessionid + 1
        send_package(client_fd, send_request(name, data, reportsessionid))
    elseif isRobotByUserid(userid) then
        -- 发给ai
        local seat = getPlayerSeat(userid)
        aiHandler.onMsg(seat, name, data)
    end
end

-- 发送消息给所有玩家
local function sendToAllClient(name, data)
    if not send_request then
        return 
    end

    for i, userid in pairs(playerids) do
        sendToOneClient(userid, name, data)
    end
end

-- 广播玩家信息
local function reportPlayerInfo(userid, playerid)
    local player = players[playerid]
    local status = config.PLAYER_STATUS.PLAYING
    if onlines[playerid] == nil then
        status = config.PLAYER_STATUS.LOADING
    end
    if onlines[playerid] == false then
        status = config.PLAYER_STATUS.OFFLINE
    end
    local seat = 0
    for i, id in pairs(seats) do
        if id == playerid then
            seat = i
            break
        end
    end
    if userid == 0 then
        sendToAllClient("reportGamePlayerInfo", {
            userid = playerid,
            nickname = player.nickname,
            headurl = player.headurl,
            status = status,
            seat = seat,
            sex = player.sex,
            ip = player.ip,
            province = player.province,
            city = player.city,
            ext = player.ext,
        })
    else
        sendToOneClient(userid, "reportGamePlayerInfo", {
            userid = playerid,
            nickname = player.nickname,
            headurl = player.headurl,
            status = status,
            seat = seat,
            sex = player.sex,
            ip = player.ip,
            province = player.province,
            city = player.city,
            ext = player.ext,
        })
    end
    
end

-- 玩家重新连接
local function relink(userid)
    local seat = getPlayerSeat(userid)
    logicHandler.relink(seat)
end

-- 玩家连入游戏，玩家客户端准备就绪
local function online(userid)
    if players[userid] then
        onlines[userid] = true
        -- todo: 下发对局信息
        reportPlayerInfo(0, userid)
        for id, player in pairs(players) do
            if id ~= userid then
                reportPlayerInfo(userid, id)
            end
        end

        if gameStatus == config.GAME_STATUS.WAITTING_CONNECT then
            --gameStatus = gameStatus.START
            testStart()
        elseif gameStatus == config.GAME_STATUS.START then
            relink(userid)
        end
    end
end

-- 游戏结束
local function gameEnd()
    gameStatus = config.GAME_STATUS.END
    canDestroy = true

    if canDestroy then
        --gameManager.destroyGame(gameid, roomid)
        skynet.send(gameManager, "lua", "destroyGame", gameid, roomid)
    end
    pushLog(config.LOG_TYPE.GAME_END, 0, gameid, roomid, "")
end

-- 检查桌子状态，如果超时，则销毁桌子
local function checkRoomStatus()
    if gameStatus == config.GAME_STATUS.WAITTING_CONNECT then
        local timeNow = os.time()
        if timeNow - createRoomTime > config.WAITTING_CONNECT_TIME then
            --testStart()
            gameEnd()
        end
    elseif gameStatus == config.GAME_STATUS.START then
        local timeNow = os.time()
        if timeNow - gameStartTime > config.GAME_TIME then
            gameEnd()
        end
    end
end

------------------------------------------------------------------------------------------------------------ ai消息处理
-- 处理ai消息
function roomHandlerAi.onAiMsg(seat, name, data)
    log.info("roomHandlerAi.onMsg", seat, name, data)
    local f = XY[name]
    if f then
        local userid = seats[seat]
        f(userid, data)
    end
end

------------------------------------------------------------------------------------------------------------ room接口，提供给logic调用
-- room接口,发送消息给单个玩家
function roomHandler.sendToOneClient(seat, name, data)
    local userid = seats[seat]
    sendToOneClient(userid, name, data)
end

-- room接口,发送消息给所有玩家
function roomHandler.sendToAllClient(name, data)
    sendToAllClient(name, data)
end

-- room接口,游戏结果
function roomHandler.gameResult(data)
    for k, v in pairs(data) do
        local userid = seats[v.seat]
        local flag = config.RESULT_TYPE.NONE
        local addType = "other"
        if v.endResult == 1 then
            flag = config.RESULT_TYPE.WIN
            addType = "win"
        elseif v.endResult == 2 then
            flag = config.RESULT_TYPE.DRAW
            addType = "draw"
        else 
            flag = config.RESULT_TYPE.LOSE
            addType = "lose"
        end
        local tmp = {
            seats = seats,
            data = data,
        }
        pushLogResult(config.LOG_RESULT_TYPE.GAME_END, userid, gameid, roomid, flag, 0, 0, 0, 0, 0, cjson.encode(tmp))

        pushUserGameRecords(userid, gameid, addType, 1)
    end
end

-- room接口,游戏结束
function roomHandler.gameEnd()
    gameEnd()
end

------------------------------------------------------------------------------------------------------------ 客户端发上来的协议
-- 玩家准备就绪
function XY.gameReady(userid, args)
    local playerStatus = {
        userid = userid,
        status = 1
    }

    sendToAllClient("reportGamePlayerStatus", playerStatus)
end

-- 玩家出招
function XY.gameOutHand(userid, args)
    local seat = getPlayerSeat(userid)
    if seat then
        logicHandler.outHand(seat, args)
    end
end

-- region 命令接口
------------------------------------------------------------------------------------------------------------ 命令接口
local CMD = {}
-- 玩家进入游戏
function CMD.playerEnter(userData)
    if players[userData.userid] then
        log.info("玩家已经在游戏中 %s", userData.userid)
        return false
    end
    players[userData.userid] = userData
    -- 分配座位信息
    table.insert(seats, userData.userid)
    return true
end

-- 初始化游戏逻辑
function CMD.start(data)
    log.info("game10001 start %s", UTILS.tableToString(data))
    roomid = data.roomid
    gameid = data.gameid
    playerids = data.players
    gameData = data.gameData
    gameManager = data.gameManager
    logicHandler.init(#playerids, gameData.rule, roomHandler)
    aiHandler.init(roomHandlerAi)
    createRoomTime = os.time()
    skynet.fork(function()
        while true do
            skynet.sleep(dTime)
            logicHandler.update()
            aiHandler.update()
            checkRoomStatus()
        end
    end)
    gameStatus = config.GAME_STATUS.WAITTING_CONNECT

    -- 创建房间日志
    local ext = {
        playerids = playerids,
        gameData = gameData
    }
    local extstr = cjson.encode(ext)
    pushLog(config.LOG_TYPE.CREATE_ROOM, 0, gameid, roomid, extstr)
end

-- 客户端消息处理
function CMD.onClinetMsg(userid, name, args, response)
    log.info("onClinetMsg %s", name)
    local f = XY[name]
    if f then
        f(userid, args)
    end
end

-- 连接游戏
function CMD.connectGame(userid, client_fd, agent)
    log.info("connectGame %d", userid)
    client_fds[userid] = client_fd
    agents[userid] = agent
    online(userid)
    return true
end

function CMD.stop()
    -- 清理玩家
    for userid, agent in pairs(agents) do
        skynet.send(agent, "lua", "leaveGame")
    end

    if gameData.robots and #gameData.robots > 0 then
        local robotManager = skynet.localname(".robotManager")
        if robotManager then
            skynet.send(robotManager, "lua", "returnRobots", gameData.robots)
        end
    end

    pushLog(config.LOG_TYPE.DESTROY_ROOM, 0, gameid, roomid, "")
    skynet.exit()
end

function CMD.offLine(userid)
    if players[userid] and onlines[userid] then
        onlines[userid] = false
        reportPlayerInfo(0, userid)
    end
end
------------------------------------------------------------------------------------------------------------

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        end
    end)
    host = sprotoloader.load(1):host "package"
    send_request = host:attach(sprotoloader.load(2))
    gate = skynet.localname(".wsGateserver")
end)