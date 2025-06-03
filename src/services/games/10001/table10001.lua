local skynet = require "skynet"
require "skynet.manager"
local logic = require "logic10001"
local sprotoloader = require "sprotoloader"
local CMD = {}
local name = "game10001"
local roomid = 0
local gameid = 0
local playerids = {}
local gameData = {}
local players = {}
local onlines = {}
local client_fds = {}
local gameStatus = {
    NOT_START = 0,
    START = 1,
    END = 2
}
local host
local gate
local gameStatus = gameStatus.NOT_START
local XY = {}
local reportsessionid = 0
-- 更新玩家状态
-- 收发协议
-- 游戏逻辑
-- 销毁逻辑
-- 未开局销毁逻辑

-- 开始游戏
local function startGame()
    gameStatus = gameStatus.START
    logic.startGame()
    LOG.info("game start")
end

-- 测试是否可以开始游戏
local function testStart()
    LOG.info("testStart")
    local onlineCount = 0
    for _, playerid in pairs(playerids) do
        if onlines[playerid] then
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
    skynet.call(gate, "lua", "send", client_fd, pack)
end

-- 发送消息给单个玩家
local function sendToOneClient(userid, name, data)
    local client_fd = client_fds[userid]
    if client_fd then
        reportsessionid = reportsessionid + 1
        send_request = host:attach(sprotoloader.load(2))
        send_package(client_fd, send_request(name, data, reportsessionid))
    end
end

-- 发送消息给所有玩家
local function sendToAllClient(name, data)
    reportsessionid = reportsessionid + 1
    send_request = host:attach(sprotoloader.load(2))
    for _, client_fd in pairs(client_fds) do
        send_package(client_fd, send_request(name, data, reportsessionid))
    end
end

-- 玩家准备就绪
function XY.gameReady(userid, args)
    local playerStatus = {
        gameid = gameid,
        roomid = roomid,
        userid = userid,
        status = 1
    }

    sendToAllClient("reportGamePlayerStatus", playerStatus)
end

-- 玩家连入游戏，玩家客户端准备就绪
function CMD.online(userid)
    if players[userid] then
        onlines[userid] = true
        -- todo: 下发对局信息

        if gameStatus == gameStatus.NOT_START then
            --gameStatus = gameStatus.START
            testStart()
        end
    end
end

-- 玩家进入游戏
function CMD.playerEnter(userData)
    if players[userData.userid] then
        LOG.info("玩家已经在游戏中 %s", userData.userid)
        return false
    end
    players[userData.userid] = userData
    return true
end

-- 初始化游戏逻辑
function CMD.start(data)
    LOG.info("game10001 start %s", UTILS.tableToString(data))
    roomid = data.roomid
    gameid = data.gameid
    playerids = data.players
    gameData = data.gameData
    logic.init(#playerids, gameData.rule)
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
function CMD.connectGame(userid, client_fd)
    LOG.info("connectGame %d", userid)
    client_fds[userid] = client_fd
    return true
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        end
    end)
    host = sprotoloader.load(1):host "package"
    gate = skynet.localname(".wsgateserver")
end)