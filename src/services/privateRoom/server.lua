-- match.lua
-- 匹配服务，负责玩家匹配逻辑和队列管理
local skynet = require "skynet"
local log = require "log"
local CMD = {}
require "skynet.manager"
-- 启动匹配服务，定时检查所有队列


-----------------------------------------------------------------------------------------

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
    skynet.register(CONFIG.SVR_NAME.PRIVATE_ROOM)
end)