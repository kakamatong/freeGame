-- wsgateserver.lua
-- WebSocket 网关服务器底层实现，负责监听端口、管理连接和消息转发
local skynet = require "skynet"
local netpack = require "skynet.netpack"
local websocket = require "http.websocket"
local wsgateserver = {}

local socket = require "skynet.socket"
local queue -- 消息队列
local maxclient -- 最大客户端连接数
local client_number = 0 -- 当前客户端连接数
-- 命令表，带有垃圾回收功能
local CMD = setmetatable({}, { __gc = function() netpack.clear(queue) end })
local nodelay = false -- 是否启用无延迟模式

local connection = {} -- 连接状态表
-- true : 已连接
-- nil : 已关闭
-- false : 关闭读取

-- 打开客户端连接，记录连接信息
function wsgateserver.openclient(fd)
	connection[fd] = {}
end

-- 关闭客户端连接，释放资源
function wsgateserver.closeclient(fd)
	local c = connection[fd]
	if c ~= nil then
		connection[fd] = nil
		websocket.close(fd)
	end
end

-- 启动网关服务器，监听端口并处理连接
function wsgateserver.start(handler)
	assert(handler.message) -- 确保有消息处理函数
	assert(handler.connect) -- 确保有连接处理函数

	function CMD.open(source, conf)
		assert(socket)
		local address = conf.address or "0.0.0.0"
		local port = assert(conf.port)
		local protocol = "ws"
        local id = socket.listen(address, port)
        LOG.info(string.format("Listen websocket addr %s port %d protocol:%s", address, port, protocol))
        socket.start(id, function(id, addr)
            LOG.info(string.format("accept client wssocket_id: %s addr:%s", id, addr))
            local ok, err = websocket.accept(id, handler, protocol, addr)
            if not ok then
                LOG.error(err)
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
	end

	skynet.start(init)
end

return wsgateserver
