-- match.lua
-- 匹配服务，负责玩家匹配逻辑和队列管理
local skynet = require "skynet"
local log = require "log"
local CMD = {}
local dTime = 1          -- 匹配检查间隔（秒）
local match = require("match.match")
require "skynet.manager"
-- 启动匹配服务，定时检查所有队列
local function start()
    skynet.fork(function()
        while true do
            match.tick()
            skynet.sleep(dTime * 100)
        end
    end)
end

function CMD.matchJoin(...)
    return match.join(...)
end

function CMD.matchLeave(...)
    return match.leave(...)
end

function CMD.matchOnSure(...)
    return match.onSure(...)
end

function CMD.startTest()
    return match.startTest()
end

function CMD.stopTest()
    return match.stopTest()
end

function CMD.start()
    return start()
end

-----------------------------------------------------------------------------------------

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
    skynet.newservice("protoloader")
    start()
    skynet.register(CONFIG.SVR_NAME.MATCH)
end)