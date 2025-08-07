local skynet = require "skynet"
local log = require "log"
local CMD = {}
local allGames = {}
local snowflake = require "snowflake"
local config = require "games.config"
local sharedata = require "skynet.sharedata"
local parser = require "sprotoparser"
require "skynet.manager"
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
        local c2s = "game" .. gameid .. "_c2s"
        sharedata.new(c2s, data)
        --sharedata.query(c2s)

        filename = "proto/" .. string.format("game%d", gameid) .. "/s2c.sproto"
        bin = loadfile(filename)
        data = {
            str = bin,
        }
        local s2c = "game" .. gameid .. "_s2c"
        sharedata.new(s2c, data)
        --sharedata.query(s2c)
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
    local roomid = snowflake.generate()
    local addr = skynet.getenv("clusterName")
    local name = "games/" .. gameid .. "/room"
    local game = skynet.newservice(name)
    skynet.call(game, "lua", "start", {gameid = gameid, players = players, gameData = gameData, roomid = roomid, addr = addr, gameManager = skynet.self()})
    if not allGames[gameid] then
        allGames[gameid] = {}
    end
    allGames[gameid][roomid] = game
    
    return roomid,addr
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
    local b, room = checkHaveRoom(gameid, roomid)
    return b
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
        log.info("dispatch %s %s", cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    skynet.register(CONFIG.SVR_NAME.GAMES)
    start()
end)