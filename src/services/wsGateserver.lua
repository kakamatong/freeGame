-- wsGateserver.lua
-- WebSocket 网关服务器底层实现，负责监听端口、管理连接和消息转发
local skynet = require "skynet"
local netpack = require "skynet.netpack"
local websocket = require "http.websocket"
local socket = require "skynet.socket"

require "skynet.manager"
local wsGateserver = {}
local log = require "log"
local queue -- 消息队列
-- 命令表，带有垃圾回收功能
local CMD = setmetatable({}, { __gc = function() netpack.clear(queue) end })
local name = ".wsGateserver"
local connection = {} -- 连接状态表

-- 打开客户端连接，记录连接信息
function wsGateserver.openclient(fd, handler, protocol, addr, options)
	connection[fd] = {}
end

-- 关闭客户端连接，释放资源
function wsGateserver.closeclient(fd)
	local c = connection[fd]
	if c ~= nil then
		connection[fd] = nil
	end
	websocket.close(fd)
end

-- 启动网关服务器，监听端口并处理连接
function wsGateserver.start(handler, newName)
	assert(handler.message) -- 确保有消息处理函数
	assert(handler.connect) -- 确保有连接处理函数
	assert(handler.auth) -- 确保有连接处理函数

	function CMD.open(source, conf)
		assert(socket)
		local address = conf.address or "0.0.0.0"
		local port = assert(conf.port)
		local protocol = conf.protocol or "ws"
        local id = socket.listen(address, port)
        log.info(string.format("Listen websocket addr %s port %d protocol:%s", address, port, protocol))
        socket.start(id, function(fd, addr)
            log.info(string.format("accept client wssocket_id: %s addr:%s", fd, addr))
			local ok, err = websocket.accept(fd, handler, protocol, addr)
			if not ok then
				socket.close(id)
				log.error("wsGateserver.websocket.accept error:%s", err)
				return 
			end
        end)

		if handler.open then
			return handler.open(source, conf)
		end
	end

	-- 关闭监听（未实现）
	function CMD.close()
		assert(socket)
		--socketdriver.close(socket)
	end
	
	-- 初始化函数，分发命令和消息
	local function init()
		skynet.dispatch("lua", function (_, address, cmd, ...)
			local f = CMD[cmd]
			if f then
				skynet.ret(skynet.pack(f(address, ...)))
			else
				skynet.ret(skynet.pack(handler.command(cmd, address, ...)))
			end
		end)
		local svrName = newName or name
		log.info("wsGateserver start %s", svrName)
		skynet.register(svrName)
	end

	skynet.start(init)
end

return wsGateserver