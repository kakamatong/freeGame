local skynet = require "skynet"
local log = require "log"
local CMD = {}
local allGames = {}
local roomid = os.time() * 100000
local config = require "games.config"
local sharedata = require "skynet.sharedata"
local parser = require "sprotoparser"

local function loadfile(filename)
    local f = assert(io.open(filename), "Can't open sproto file")
    local data = f:read "a"
    f:close()
    return parser.parse(data)
end

local function loadSproto()
    for _, gameid in ipairs(config.gameids) do
        local filename = "proto/" .. string.format("game%d", gameid) .. "/c2s.sproto"
        local bin = loadfile(filename)
        local data = {
            str = bin,
        }
        sharedata.new("game" .. gameid .. "_c2s", data)

        filename = "proto/" .. string.format("game%d", gameid) .. "/s2c.sproto"
        bin = loadfile(filename)
        data = {
            str = bin,
        }
        sharedata.new("game" .. gameid .. "_s2c", data)
    end
end

local function start()
    local ok,err = pcall(loadSproto)
    if not ok then
        log.error("loadSproto error %s", err)
    end
end

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
function CMD.checkHaveRoom(gameid,roomid)
    return checkHaveRoom(gameid, roomid)
end

-- 获取游戏
function CMD.getGame(gameid,roomid)
    local b,room = checkHaveRoom(gameid, roomid)
    return room
end

-- 连接游戏
function CMD.connectGame(userid,gameid,roomid,client_fd) 
    log.info("connectGame %d %d %d %d", gameid, roomid, userid, client_fd)
    local b, room = checkHaveRoom(gameid, roomid)
    if not b or not room then
        log.error("room not found %s %s", gameid, roomid)
        return
    end
    return skynet.call(room, "lua", "connectGame", userid, client_fd)
end

-- 玩家断线
function CMD.offLine(userid,gameid,roomid)
    local b, room = checkHaveRoom(gameid, roomid)
    if not b or not room then
        log.error("game not found %s %s", gameid, roomid)
        return false
    end
    skynet.send(room, "lua", "offLine", userid)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    
    start()
end)