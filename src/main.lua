-- main.lua
-- 游戏服务器主入口，负责启动各个核心服务
local skynet = require "skynet"
local sprotoloader = require "sprotoloader"

local max_client = 64 -- 最大客户端连接数

skynet.start(function()
	-- 启动协议加载服务（用于sproto协议）
	skynet.uniqueservice("protoloader")
	-- 如果不是守护进程，则启动控制台服务
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	-- 启动调试控制台，监听8000端口
	--skynet.newservice("debug_console","0.0.0.0",8000)
	skynet.newservice("debug_console",8000)

	skynet.newservice("gameManager")

	-- 启动匹配服务
	local match = skynet.newservice("match")
	skynet.call(match, "lua", "start")

	-- 启动数据库服务
	local dbserver = skynet.newservice("dbserver")
	skynet.call(dbserver, "lua", "cmd", "start")
	--skynet.newservice("simpledb")
	-- 启动WebSocket登录服务
	local loginservice = skynet.newservice("wsAuthd")

	-- 启动WebSocket网关服务器
	local wswatchdog = skynet.newservice("wsWatchdog")
	local addr,port = skynet.call(wswatchdog, "lua", "start", {
		address = "0.0.0.0",
		port = 9002,
		maxclient = max_client,
		-- onOpen = function(source) -- 向登入认证服务注册网关
		-- 	skynet.call(loginservice, "lua", "register_gate", "lobbyGate", source)
		-- end,
	})
	LOG.info("Wswatchdog listen on " .. addr .. ":" .. port)
	-- 启动完成后退出主服务
	skynet.exit()
end)
