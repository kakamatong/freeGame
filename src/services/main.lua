-- main.lua
-- 游戏服务器主入口，负责启动各个核心服务
local skynet = require "skynet"
local cluster = require "skynet.cluster"
local log = require "log"

local function createDebugConsoleSvr(port)
	-- 启动调试控制台
	skynet.newservice("debug_console",port)
end

local function createGateSvr()
	-- 启动协议加载服务（用于sproto协议）
	skynet.newservice("protoloader")
	-- 启动网关服务
	local svr = skynet.newservice("wsWatchdog")
	skynet.call(svr, "lua", "start", CONFIG.WS_GATE_LISTEN)
	local gate = skynet.localname(CONFIG.SVR_NAME.GATE)
	cluster.register(CONFIG.CLUSTER_SVR_NAME.GATE, gate)
end

local function createGameSvr()
	local svr = skynet.newservice("wsGameGate")
	skynet.call(svr, "lua", "open", CONFIG.WS_GAME_GATE_LISTEN)
	local svrGame = skynet.newservice("games/server")
	cluster.register(CONFIG.CLUSTER_SVR_NAME.GAMES, svrGame)
end

local function createCommonSvr(path, name)
	local svr = skynet.newservice(path)
	if name then
		cluster.register(name, svr)
	end
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
	createCommonSvr("db/server")

	local svrManager = skynet.newservice("clusterManager/server")
	skynet.call(svrManager, "lua", "start")

	local open = skynet.getenv(CONFIG.CLUSTER_SVR_NAME.MATCH)
	if open then
		skynet.newservice("protoloader")
		createCommonSvr("match/server", CONFIG.CLUSTER_SVR_NAME.MATCH)
	end

	open = skynet.getenv(CONFIG.CLUSTER_SVR_NAME.AUTH)
	if open then
		createCommonSvr("auth/server", CONFIG.CLUSTER_SVR_NAME.AUTH)
	end

	open = skynet.getenv(CONFIG.CLUSTER_SVR_NAME.USER)
	if open then
		createCommonSvr("user/server", CONFIG.CLUSTER_SVR_NAME.USER)
	end

	open = skynet.getenv(CONFIG.CLUSTER_SVR_NAME.ACTIVITY)
	if open then
		createCommonSvr("activity/server", CONFIG.CLUSTER_SVR_NAME.ACTIVITY)
	end

	open = skynet.getenv(CONFIG.CLUSTER_SVR_NAME.ROBOT)
	if open then
		createCommonSvr("robot/server", CONFIG.CLUSTER_SVR_NAME.ROBOT)
	end

	open = skynet.getenv(CONFIG.CLUSTER_SVR_NAME.GATE)
	if open then
		createGateSvr()
	end

	open = skynet.getenv(CONFIG.CLUSTER_SVR_NAME.GAMES)
	if open then
		createGameSvr()
	end


	local name = skynet.getenv("clusterName")
	cluster.open(name)
	
	skynet.exit()
end)
