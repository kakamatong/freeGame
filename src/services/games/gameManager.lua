local skynet = require "skynet"
local log = require "log"
require "skynet.manager"

local CMD = {}
local name = "gameManager"
local allGames = {}
local roomid = os.time() * 100000

local function checkHaveRoom(gameid, roomid)
    if not allGames[gameid] then
        return false
    end
    if not allGames[gameid][roomid] then
        return false
    end

    return true
end

-- 创建游戏
function CMD.createGame(gameid, players, gameData)
    roomid = roomid + 1
    log.info("createGame %d", roomid)
    local name = "games/" .. gameid .. "/room"
    local game = skynet.newservice(name)
    skynet.call(game, "lua", "start", {gameid = gameid, players = players, gameData = gameData, roomid = roomid , gameManager = skynet.self()})
    if not allGames[gameid] then
        allGames[gameid] = {}
    end
    allGames[gameid][roomid] = game
    
    return roomid
end

-- 销毁游戏
function CMD.destroyGame(gameid, roomid)
    local game = allGames[gameid][roomid]
    allGames[gameid][roomid] = nil
    skynet.send(game, "lua", "stop")
    return true
end

-- 检查房间是否存在
function CMD.checkHaveRoom(gameid, roomid)
    return checkHaveRoom(gameid, roomid)
end

-- 获取游戏
function CMD.getGame(gameid, roomid)
    return allGames[gameid][roomid]
end

-- 玩家进入游戏
function CMD.playerEnter(gameid, roomid, userData)
    local game = allGames[gameid][roomid]
    if not game then
        log.error("game not found %s %s", gameid, roomid)
        return false
    end
    local ret = skynet.call(game, "lua", "playerEnter", userData)
    
    return ret
end

-- 客户端消息处理
function CMD.onClinetMsg(userid, name, args)
    log.info("onClinetMsg %s %s %s", userid, name, args)
    local game = allGames[args.gameid][args.roomid]
    if not game then
        log.error("game not found %s %s", args.gameid, args.roomid)
        return false
    end
    local ret = skynet.send(game, "lua", "onClinetMsg", userid, name, args)
    return ret
end

-- 连接游戏
function CMD.connectGame(gameid, roomid, userid, client_fd)
    log.info("connectGame %s %s %s %s", gameid, roomid, userid, client_fd)
    log.info("table: %s", UTILS.tableToString(allGames))
    local game = allGames[gameid][roomid]
    if not game then
        log.error("game not found %s %s", gameid, roomid)
        return
    end
    local ret = skynet.call(game, "lua", "connectGame", userid, client_fd)
    return ret
end

-- 玩家断线
function CMD.offLine(gameid, roomid, userid)
    local game = allGames[gameid][roomid]
    if not game then
        log.error("game not found %s %s", gameid, roomid)
        return false
    end
    skynet.send(game, "lua", "offLine", userid)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            skynet.ignoreret()
            log.error("gameManager cmd not found %s", cmd)
        end
    end)
    skynet.register("." .. name)
end)