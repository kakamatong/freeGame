-- main.lua
-- 游戏服务器主入口，负责启动各个核心服务
local skynet = require "skynet"
local cluster = require "skynet.cluster"
local log = require "log"
local gConfig = CONFIG
local cjson = require "cjson"

skynet.start(function()
	-- 启动协议加载服务（用于sproto协议）
	skynet.newservice("protoloader")
	-- 如果不是守护进程，则启动控制台服务
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	-- 启动调试控制台，监听8000端口
	local consolePort = skynet.getenv("debugConsolePort")
	skynet.newservice("debug_console",consolePort)

	skynet.newservice("db/server")
	local svrMatch = skynet.newservice("match/server")

	local svrManager = skynet.newservice("clusterManager/server")
	skynet.call(svrManager, "lua", "start")
	cluster.register("match", svrMatch)

	local name = skynet.getenv("clusterName")
	cluster.open(name)

	-- local list = {}
	-- list.ver = 1
	-- local data = {}
	-- data.match = {"127.0.0.1:13001"}
	-- data.lobby = {"127.0.0.1:13006"}
	-- data.robot = {"127.0.0.1:13007"}
	-- data.gate = {"127.0.0.1:13005"}
	-- data.game = {"127.0.0.1:13002"}
	-- data.login = {"127.0.0.1:13004"}
	-- list.list = data
	-- local str = cjson.encode(list)
	-- local db = skynet.localname(CONFIG.SVR_NAME.DB)
	-- skynet.call(db, "lua", "dbRedis", "set", "clusterConfig", str)
	
	skynet.exit()
end)
