-- wsGateserver.lua
-- WebSocket 网关服务器底层实现，负责监听端口、管理连接和消息转发
local skynet = require "skynet"
local netpack = require "skynet.netpack"
local websocket = require "http.websocket"
local socket = require "skynet.socket"
local sockethelper = require "http.sockethelper"
local internal = require "http.internal"

require "skynet.manager"
local wsGateserver = {}
local log = require "log"
local queue -- 消息队列
-- 命令表，带有垃圾回收功能
local CMD = setmetatable({}, { __gc = function() netpack.clear(queue) end })
local name = ".wsGateserver"
local connection = {} -- 连接状态表
-- true : 已连接
-- nil : 已关闭
-- false : 关闭读取

local function getOptions(socket_id, protocol)
	local options = nil
	local read = nil
	if protocol == "ws" then
		read = sockethelper.readfunc(socket_id)
	elseif protocol == "wss" then
		local tls = require "http.tlshelper"
		if not SSLCTX_SERVER then
			SSLCTX_SERVER = tls.newctx()
			-- gen cert and key
			-- openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout server-key.pem -out server-cert.pem
			local certfile = skynet.getenv("certfile") or "./server-cert.pem"
			local keyfile = skynet.getenv("keyfile") or "./server-key.pem"
			SSLCTX_SERVER:set_cert(certfile, keyfile)
		end
		local tls_ctx = tls.newtls("server", SSLCTX_SERVER)
		read = tls.readfunc(socket_id, tls_ctx)
	else
		error(string.format("invalid websocket protocol:%s", tostring(protocol)))
	end

	if read then
		local tmpline = {}
        local payload = internal.recvheader(read, tmpline, "")
        if not payload then
            return options
        end

        local request = assert(tmpline[1])
        local method, url, httpver = request:match "^(%a+)%s+(.-)%s+HTTP/([%d%.]+)$"
        assert(method and url and httpver)
        if method ~= "GET" then
            return options
        end

        httpver = assert(tonumber(httpver))
        if httpver < 1.1 then
            return options  -- HTTP Version not supported
        end
        local header = internal.parseheader(tmpline, 2, {})
		options = {
			upgrade = {
				header = header,
				url = url,
				method = method,
			}
		}
	end
	return options
end

-- 打开客户端连接，记录连接信息
function wsGateserver.openclient(fd, handler, protocol, addr, options)
	log.info("options %s", UTILS.tableToString(options))
	connection[fd] = {}
	local ok, err = websocket.accept(fd, handler, protocol, addr, options)
	if not ok then
		log.error("wsGateserver.openclient error:%s", err)
		return 
	end
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

	local function auth(socket_id, protocol, addr)
		local isok, err = socket.start(socket_id)
        if not isok then
            return false, err
        end

		local options = getOptions(socket_id, protocol)
		if not options then
			return false, "invalid websocket request"
		end

		local ok, userid = handler.auth(socket_id, options.upgrade.url, addr)
		if not ok then
			return false, "auth failed"
		end
		options.userid = userid

		return true, options
	end

	function CMD.open(source, conf)
		assert(socket)
		local address = conf.address or "0.0.0.0"
		local port = assert(conf.port)
		local protocol = "ws"
        local id = socket.listen(address, port)
        log.info(string.format("Listen websocket addr %s port %d protocol:%s", address, port, protocol))
        socket.start(id, function(id, addr)
            log.info(string.format("accept client wssocket_id: %s addr:%s", id, addr))
			local ok ,info = auth(id, protocol, addr)
            if not ok then
                log.error(info)
				socket.close(id)
				return
            end
			handler.authSuccess(id, info, protocol, addr)
			
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