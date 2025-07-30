-- main.lua
-- 游戏服务器主入口，负责启动各个核心服务
local skynet = require "skynet"
local cluster = require "skynet.cluster"
local log = require "log"
local gConfig = CONFIG

skynet.start(function()
	-- 启动协议加载服务（用于sproto协议）
	skynet.newservice("protoloader")
	-- 如果不是守护进程，则启动控制台服务
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	-- 启动调试控制台，监听8000端口
	-- local consolePort = skynet.getenv("debugConsolePort")
	-- skynet.newservice("debug_console",consolePort)

	skynet.newservice("db/server")
	local svrGame = skynet.newservice("games/server")
	cluster.register("game", svrGame)

	cluster.open("game")
	skynet.exit()
end)
