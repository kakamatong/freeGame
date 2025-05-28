local skynet = require "skynet"
local wsgateserver = require "wsgateserver"
local websocket = require "http.websocket"
local watchdog
local connection = {}	-- fd -> connection : { fd , client, agent , ip, mode } 链接池
local logins = {}	-- uid -> login : { uid, login } 登入池子

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
}

local function register_handler(name)
	LOG.info("wsgate register_handler")
	local loginservice = skynet.localname(".ws_login_master")
	if loginservice then
		skynet.call(loginservice, "lua", "register_gate", name, skynet.self())
	else
		LOG.error("wsgate register_handler error")
	end
end

local handler = {}

function handler.open(source, conf)
	LOG.info("wsgate open")
	watchdog = conf.watchdog or source
	register_handler("lobbyGate") -- 注册到login服务
	return conf.address, conf.port
end

function handler.message(fd, msg, msgType)
	LOG.info("wsgate message")
	-- recv a package, forward it
	local c = connection[fd]
	local agent = c.agent
	if agent then
		LOG.info("wsgate message forward")
		-- It's safe to redirect msg directly , gateserver framework will not free msg.
		skynet.redirect(agent, c.client, "client", fd, msg, string.len(msg))
	else
		LOG.info("wsgate message send")
		skynet.send(watchdog, "lua", "socket", "data", fd, msg)
		-- skynet.tostring will copy msg to a string, so we must free msg here.
		skynet.trash(msg,string.len(msg))
	end
end

function handler.connect(fd)
	LOG.info("wsgate connect")
end

function handler.handshake(fd, header, url)
	local addr = websocket.addrinfo(fd)
	LOG.info("wsgate handshake from: %s, url %s, addr %s" ,tostring(fd), url, addr)

	local c = {
		fd = fd,
		ip = addr,
		url = url,
		header = header,
	}
	connection[fd] = c
	skynet.send(watchdog, "lua", "socket", "open", fd, addr)
	wsgateserver.openclient(fd)
end

local function unforward(c)
	if c.agent then
		c.agent = nil
		c.client = nil
	end
end

local function clearLogin(c)
	if c.userid then
		logins[c.userid] = nil
	end
end

local function kickByUserid(userid)
	local c = logins[userid]
	if c then
		wsgateserver.closeclient(c.fd)
	end
end

local function close_fd(fd)
	local c = connection[fd]
	if c then
		clearLogin(c)
		unforward(c)
		connection[fd] = nil
	end
end

function handler.close(fd)
	LOG.info("wsgate close")
	close_fd(fd)
	skynet.send(watchdog, "lua", "socket", "close", fd)
end

function handler.error(fd, msg)
	LOG.info("wsgate error")
	close_fd(fd)
	skynet.send(watchdog, "lua", "socket", "error", fd, msg)
end

local CMD = {}

function CMD.forward(source, fd, client, address)
	LOG.info("wsgate forward")
	local c = assert(connection[fd])
	unforward(c)
	c.client = client or 0
	c.agent = address or source
	skynet.call(c.agent, "lua", "content")
end

function CMD.send(source, fd, msg)
	websocket.write(fd, msg, "binary")
end

function CMD.accept(source, fd)
	local c = assert(connection[fd])
	unforward(c)
	wsgateserver.openclient(fd)
end

function CMD.kick(source, fd)
	LOG.info("wsgate kick")
	wsgateserver.closeclient(fd)
end

function CMD.authSuccess(source,userid, fd)
	local c = assert(connection[fd])
	c.userid = userid
end

function CMD.login(source, userid, secret,loginType)
	-- todo: 将uid和secret写入数据库
	local dbserver = skynet.localname(".dbserver")
	if not dbserver then
		LOG.error("wsgate login error: dbserver not started")
		return
	end
	-- 踢掉之前的链接
	kickByUserid(userid)
	
	local subid = skynet.call(dbserver, "lua", "func", "setAuth", userid, secret, 0, loginType)

	return subid or -1
end

function handler.command(cmd, source, ...)
	local f = assert(CMD[cmd])
	return f(source, ...)
end

wsgateserver.start(handler)
