local skynet = require "skynet"
require "skynet.manager"

local CMD = {}
local name = "game10001"
local roomid = 0
local gameid = 0
local playerids = {}
local gameData = {}

function CMD.start(data)
    LOG.info("game10001 start %s", UTILS.tableToString(data))
    roomid = data.roomid
    gameid = data.gameid
    playerids = data.players
    gameData = data.gameData
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        end
    end)
end)