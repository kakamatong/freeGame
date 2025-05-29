local skynet = require "skynet"
require "skynet.manager"
local logic = require "logic10001"
local CMD = {}
local name = "game10001"
local roomid = 0
local gameid = 0
local playerids = {}
local gameData = {}
local players = {}
local onlines = {}
local gameStatus = {
    NOT_START = 0,
    START = 1,
    END = 2
}
local gameStatus = gameStatus.NOT_START
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

-- 玩家在线，玩家客户端准备就绪
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

function CMD.playerEnter(userData)
    if players[userData.userid] then
        LOG.info("玩家已经在游戏中 %s", userData.userid)
        return
    end
    players[userData.userid] = userData
end

function CMD.start(data)
    LOG.info("game10001 start %s", UTILS.tableToString(data))
    roomid = data.roomid
    gameid = data.gameid
    playerids = data.players
    gameData = data.gameData
    logic.init(#playerids, gameData.rule)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        end
    end)
end)