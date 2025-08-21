-- match.lua
-- 匹配服务，负责玩家匹配逻辑和队列管理
local skynet = require "skynet"
local log = require "log"
local CMD = {}
require "skynet.manager"
local svrDB = nil

-- 创建私人房间
function CMD.createPrivateRoom(...)
	local userid,gameid,rule = ...
	local players = {}
	table.insert(players,userid)
	local gameData = {
		rule = rule,
	}
	return call(CONFIG.CLUSTER_SVR_NAME.GAME, "createPrivateGameRoom", gameid,players,gameData)
end

function CMD.joinPrivateRoom(...)
	local userid,shortRoomid = ...
	return skynet.call(svrDB, "lua", "db", "getPrivateRoomid", shortRoomid)
end

-----------------------------------------------------------------------------------------

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
	svrDB = skynet.localname(CONFIG.SVR_NAME.DB)
    skynet.register(CONFIG.SVR_NAME.PRIVATE_ROOM)
end)