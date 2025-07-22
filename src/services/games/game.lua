local skynet = require "skynet"
local log = require "log"

local game = {}

local allGames = {}
local roomid = os.time() * 100000

local function checkHaveRoom(gameid, roomid)
    local games = allGames[gameid]
    if not allGames[gameid] then
        return false
    end
    local room = games[roomid]
    if not room then
        return false
    end

    return true, room
end

-- 创建游戏
function game.createGame(args)
    local gameid = args.gameid
    local players = args.players
    local gameData = args.gameData
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
function game.destroyGame(args)
    local gameid = args.gameid
    local roomid = args.roomid
    local b, room = checkHaveRoom(gameid, roomid)
    if not b or not room then
        log.error("game not found %s %s", gameid, roomid)
        return false
    end
    allGames[gameid][roomid] = nil
    skynet.send(room, "lua", "stop")
    return true
end

-- 检查房间是否存在
function game.checkHaveRoom(args)
    return checkHaveRoom(args.gameid, args.roomid)
end

-- 获取游戏
function game.getGame(args)
    local b,room = checkHaveRoom(args.gameid, args.roomid)
    return room
end

-- 连接游戏
function game.connectGame(args) 
    local gameid = args.gameid
    local roomid = args.roomid
    local userid = args.userid
    local client_fd = args.client_fd
    log.info("connectGame %d %d %d %d", gameid, roomid, userid, client_fd)
    local b, room = checkHaveRoom(gameid, roomid)
    if not b or not room then
        log.error("room not found %s %s", gameid, roomid)
        return
    end
    return skynet.call(room, "lua", "connectGame", userid, client_fd)
end

-- 玩家断线
function game.offLine(args)
    local gameid = args.gameid
    local roomid = args.roomid
    local userid = args.userid
    local b, room = checkHaveRoom(gameid, roomid)
    if not b or not room then
        log.error("game not found %s %s", gameid, roomid)
        return false
    end
    skynet.send(room, "lua", "offLine", userid)
end

return game