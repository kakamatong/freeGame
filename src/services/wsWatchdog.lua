-- wswatchdog.lua
-- WebSocket 网关看门狗服务，负责管理客户端连接和分发
local skynet = require "skynet"
local log = require "log"
local CMD = {}
local SOCKET = {}
local gate
local agent = {}

-- 新客户端连接时调用，创建新的agent服务
function SOCKET.open(fd, addr, ip, userid)
	log.info("New client from : " .. addr)
	agent[fd] = skynet.newservice("agent")
	skynet.call(agent[fd], "lua", "start", { gate = gate, client = fd, watchdog = skynet.self(), addr = addr, ip = ip, userid = userid })
end

-- 关闭指定fd的agent服务
local function close_agent(fd)
	local a = agent[fd]
	agent[fd] = nil
	if a then
		--skynet.call(gate, "lua", "kick", fd)
		-- disconnect never return
		skynet.send(a, "lua", "disconnect")
	end
end

-- 客户端断开连接时调用
function SOCKET.close(fd)
	log.info("socket close",fd)
	close_agent(fd)
end

-- 连接出错时调用
function SOCKET.error(fd, msg)
	log.info("socket error",fd, msg)
	close_agent(fd)
end

-- 收到数据时调用（此处未处理）
function SOCKET.data(fd, msg)
end

-- 启动网关服务
function CMD.start(conf)
	return skynet.call(gate, "lua", "open" , conf)
end

-- 主动关闭某个连接
function CMD.close(fd)
	close_agent(fd)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if cmd == "socket" then
			local f = SOCKET[subcmd]
			f(...)
			-- socket api don't need return
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)

	gate = skynet.newservice("wsGate")
end)
