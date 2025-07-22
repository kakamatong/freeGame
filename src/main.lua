-- main.lua
-- 游戏服务器主入口，负责启动各个核心服务
local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local log = require "log"
local gConfig = CONFIG
skynet.start(function()
	-- 启动协议加载服务（用于sproto协议）
	skynet.uniqueservice("protoloader")
	-- 如果不是守护进程，则启动控制台服务
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	-- 启动调试控制台，监听8000端口
	--skynet.newservice("debug_console","0.0.0.0",8000)
	skynet.newservice("debug_console",gConfig.DEBUG_CONSOLE_PORT)

	-- 启动数据库服务
	skynet.newservice("db/server")

	-- 启动认证服务
	skynet.newservice("auth/server")

	-- 签到服务
	skynet.newservice("activity/server")

	-- 大厅服务
	skynet.newservice("lobby/server")

	-- 用户服务
	skynet.newservice("user/server")

	-- 启动游戏服务
	skynet.newservice("games/server")

	-- 启动机器人服务
	skynet.newservice("robot/server")

	-- 启动匹配服务
	skynet.newservice("match/server")

	-- 启动WebSocket登录服务
	skynet.newservice("wsLogind")

	local gameGate = skynet.newservice("wsGameGate")
	skynet.call(gameGate, "lua", "open", gConfig.WS_GAME_GATE_LISTEN)

	-- 启动WebSocket游戏网关服务器
	local wswatchdog = skynet.newservice("wsWatchdog")
	local addr,port = skynet.call(wswatchdog, "lua", "start", gConfig.WS_GATE_LISTEN)
	log.info("Wswatchdog listen on " .. addr .. ":" .. port)
	-- 启动完成后退出主服务
	skynet.exit()
end)
