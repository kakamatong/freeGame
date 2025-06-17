local skynet = require "skynet"
local config = require "games.10001.config"
require "skynet.manager"
local logicHandler = require "games.10001.logic"
local sprotoloader = require "sprotoloader"
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
local gameManager
local send_request = nil
-- 更新玩家状态
-- 收发协议
-- 游戏逻辑
-- 销毁逻辑
-- 未开局销毁逻辑

-- 开始游戏
local function startGame()
    gameStatus = config.GAME_STATUS.START
    gameStartTime = os.time()
    logicHandler.startGame()
    LOG.info("game start")
end

local function getPlayerSeat(userid)
    for i, id in pairs(seats) do
        if id == userid then
            return i
        end
    end
end

-- 测试是否可以开始游戏
local function testStart()
    LOG.info("testStart")
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
    if client_fd then
        data.gameid = gameid
        data.roomid = roomid
        --LOG.info("sendToOneClient %s", UTILS.roomToString(data))
        reportsessionid = reportsessionid + 1
        send_package(client_fd, send_request(name, data, reportsessionid))
    end
end

-- 发送消息给所有玩家
local function sendToAllClient(name, data)
    if not send_request then
        return 
    end
    data.gameid = gameid
    data.roomid = roomid
    reportsessionid = reportsessionid + 1
    for userid, client_fd in pairs(client_fds) do
        if onlines[userid] then
            send_package(client_fd, send_request(name, data, reportsessionid))
        end
    end
end

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

local function gameEnd()
    gameStatus = config.GAME_STATUS.END
    canDestroy = true

    if canDestroy then
        --gameManager.destroyGame(gameid, roomid)
        skynet.send(gameManager, "lua", "destroyGame", gameid, roomid)
    end
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

-- room接口,发送消息给单个玩家
function roomHandler.sendToOneClient(seat, name, data)
    local userid = seats[seat]
    sendToOneClient(userid, name, data)
end

-- room接口,发送消息给所有玩家
function roomHandler.sendToAllClient(name, data)
    sendToAllClient(name, data)
end

function roomHandler.gameEnd()
    gameEnd()
end

-- 玩家准备就绪
function XY.gameReady(userid, args)
    local playerStatus = {
        userid = userid,
        status = 1
    }

    sendToAllClient("reportGamePlayerStatus", playerStatus)
end

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
        LOG.info("玩家已经在游戏中 %s", userData.userid)
        return false
    end
    players[userData.userid] = userData
    -- 分配座位信息
    table.insert(seats, userData.userid)
    return true
end

-- 初始化游戏逻辑
function CMD.start(data)
    LOG.info("game10001 start %s", UTILS.tableToString(data))
    roomid = data.roomid
    gameid = data.gameid
    playerids = data.players
    gameData = data.gameData
    gameManager = data.gameManager
    logicHandler.init(#playerids, gameData.rule, roomHandler)
    createRoomTime = os.time()
    skynet.fork(function()
        while true do
            skynet.sleep(100)
            logicHandler.update()
            checkRoomStatus()
        end
    end)
    gameStatus = config.GAME_STATUS.WAITTING_CONNECT
end

-- 客户端消息处理
function CMD.onClinetMsg(userid, name, args, response)
    LOG.info("onClinetMsg %s", name)
    local f = XY[name]
    if f then
        f(userid, args)
    end
end

-- 连接游戏
function CMD.connectGame(userid, client_fd, agent)
    LOG.info("connectGame %d", userid)
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