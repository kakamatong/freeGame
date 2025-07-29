-- main.lua
-- 游戏服务器主入口，负责启动各个核心服务
local skynet = require "skynet"
local log = require "log"
local gConfig = CONFIG

local function startService(name)
	if name == "" then
		return
	end
	local svr = skynet.newservice(name)
	if name == "wsGameGate" then
		skynet.call(svr, "lua", "open", gConfig.WS_GAME_GATE_LISTEN)
	elseif name == "wsWatchdog" then
		skynet.call(svr, "lua", "start", gConfig.WS_GATE_LISTEN)
	end
end

skynet.start(function()
	-- 启动协议加载服务（用于sproto协议）
	skynet.newservice("protoloader")
	-- 如果不是守护进程，则启动控制台服务
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	-- 启动调试控制台，监听8000端口
	--skynet.newservice("debug_console","0.0.0.0",8000)
	skynet.newservice("debug_console",gConfig.DEBUG_CONSOLE_PORT)

	-- 启动需要按顺序，否则会出现获取不到服务的情况
	local strSvrList = skynet.getenv("svrList")
	log.info("----strSvrList: %s", strSvrList)
	local svrList = UTILS.string_split(strSvrList, ";")
	for _, svr in ipairs(svrList) do
		startService(svr)
	end
	-- 启动完成后退出主服务
	skynet.exit()
end)
