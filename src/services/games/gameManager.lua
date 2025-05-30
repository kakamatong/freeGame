local skynet = require "skynet"
require "skynet.manager"

local CMD = {}
local name = "gameManager"
local allGames = {}
local roomid = 0

-- 创建游戏
function CMD.createGame(gameid, players, gameData)
    roomid = roomid + 1
    local name = "game" .. gameid
    local game = skynet.newservice(name)
    skynet.call(game, "lua", "start", {gameid = gameid, players = players, gameData = gameData, roomid = roomid})
    if not allGames[gameid] then
        allGames[gameid] = {}
    end
    allGames[gameid][roomid] = game
    
    return roomid
end

-- 销毁游戏
function CMD.destroyGame(gameid, roomid)
    local game = allGames[gameid][roomid]
    skynet.call(game, "lua", "stop")
    allGames[gameid][roomid] = nil
    return true
end

-- 获取游戏
function CMD.getGame(gameid, roomid)
    return allGames[gameid][roomid]
end

function CMD.plyaerEnter(gameid, roomid, userData)
    local game = allGames[gameid][roomid]
    if not game then
        LOG.error("game not found %s %s", gameid, roomid)
        return false
    end
    local ret = skynet.call(game, "lua", "playerEnter", userData)
    
    return ret
end

function CMD.onClinetMsg(userid, name, args, response)
    local game = allGames[args.gameid][args.roomid]
    if not game then
        LOG.error("game not found %s %s", args.gameid, args.roomid)
        return false
    end
    local ret = skynet.send(game, "lua", "onClinetMsg", userid, name, args, response)
    return ret
end

function CMD.connectGame(gameid, roomid, userid, client_fd)
    local game = allGames[gameid][roomid]
    if not game then
        LOG.error("game not found %s %s", gameid, roomid)
        return false
    end
    local ret = skynet.call(game, "lua", "connectGame", userid, client_fd)
    return ret
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            skynet.ignoreret()
            LOG.error("gameManager cmd not found %s", cmd)
        end
    end)
    skynet.register("." .. name)
end)