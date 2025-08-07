-- main.lua
-- 游戏服务器主入口，负责启动各个核心服务
local skynet = require "skynet"
local cluster = require "skynet.cluster"
local log = require "log"

local function createDebugConsoleSvr(port)
	-- 启动调试控制台
	skynet.newservice("debug_console",port)
end

skynet.start(function()
	-- 如果不是守护进程，则启动控制台服务
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	
	local consolePort = skynet.getenv("debugConsolePort")
	if consolePort then
		createDebugConsoleSvr(consolePort)
	end
	skynet.newservice("db/server")

	local svrManager = skynet.newservice("clusterManager/server")
	skynet.call(svrManager, "lua", "start")
	
	skynet.exit()
end)
