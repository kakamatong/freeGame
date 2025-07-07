local skynet = require "skynet"
local wsGateserver = require "wsGateserver"
local websocket = require "http.websocket"
local urlTools = require "http.url"
local watchdog
local connection = {}	-- fd -> connection : { fd , client, agent , ip, mode } 链接池
local logins = {}	-- uid -> fd 登入池子
local log = require "log"
skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
}

local function register_handler(name)
	log.info("wsgate register_handler")
	local loginservice = skynet.localname(".ws_auth_master")
	if loginservice then
		skynet.call(loginservice, "lua", "register_gate", name, skynet.self())
	else
		log.error("wsgate register_handler error")
	end
end

-- 登入认证
local function auth(data)
	if data.userid and data.token and data.subid then
		local userid = data.userid
		local token = data.token
		local clientSubid = data.subid
		local dbserver = skynet.localname(".db")
		if not dbserver then
			return false
		end
		local key = string.format("user:%d", userid)
		local info = skynet.call(dbserver, "lua", "dbRedis", "hgetall", key)
		log.info(UTILS.tableToString(info))
		if info and info[2] == token and info[4] == clientSubid then
			return true
		end
	end
	return false
end

local handler = {}

function handler.open(source, conf)
	log.info("wsgate open")
	watchdog = conf.watchdog or source
	register_handler("lobbyGate") -- 注册到login服务
	return conf.address, conf.port
end

function handler.message(fd, msg, msgType)
	--log.info("wsgate message")
	-- recv a package, forward it
	local c = connection[fd]
	local agent = c.agent
	if agent then
		--log.info("wsgate message forward")
		-- It's safe to redirect msg directly , gateserver framework will not free msg.
		skynet.redirect(agent, c.client, "client", fd, msg, string.len(msg))
	else
		log.info("wsgate message send")
		skynet.send(watchdog, "lua", "socket", "data", fd, msg)
		-- skynet.tostring will copy msg to a string, so we must free msg here.
		skynet.trash(msg,string.len(msg))
	end
end

function handler.connect(fd)
	log.info("wsgate connect")
end

function handler.handshake(fd, header, uri)
	local addr = websocket.addrinfo(fd)
	local data = urlTools.parse_query(uri)
	log.info("wsgate handshake from: %s, uri %s, addr %s " ,tostring(fd), uri, addr)
	if auth(data) then
		local ip = websocket.real_ip(fd)
		local c = {
			fd = fd,
			addr = addr,
			uri = uri,
			header = header,
			ip = ip,
		}
		connection[fd] = c
		skynet.send(watchdog, "lua", "socket", "open", fd, addr, ip, data.userid)
		wsGateserver.openclient(fd)
	else
		wsGateserver.closeclient(fd)
	end
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
	local fd = logins[userid]
	if fd then
		wsGateserver.closeclient(fd)
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
	log.info("wsgate close")
	close_fd(fd)
	skynet.send(watchdog, "lua", "socket", "close", fd)
end

function handler.error(fd, msg)
	log.info("wsgate error")
	close_fd(fd)
	skynet.send(watchdog, "lua", "socket", "error", fd, msg)
end

local CMD = {}

function CMD.forward(source, fd, client, address)
	log.info("wsgate forward")
	local c = assert(connection[fd])
	unforward(c)
	c.client = client or 0
	c.agent = address or source
end

function CMD.send(source, fd, msg)
	if not connection[fd] then
		log.info("wsgate send error: fd not found")
		return
	end
	websocket.write(fd, msg, "binary")
end

function CMD.accept(source, fd)
	local c = assert(connection[fd])
	unforward(c)
	wsGateserver.openclient(fd)
end

function CMD.kick(source, fd)
	log.info("wsgate kick")
	wsGateserver.closeclient(fd)
end

function CMD.loginSuccess(source,userid, fd)
	local c = assert(connection[fd])
	c.userid = userid
	-- 踢掉之前的链接
	kickByUserid(userid)
	logins[userid] = fd
end

function CMD.login(source, userid, secret,loginType)
	-- todo: 将uid和secret写入数据库
	local dbserver = skynet.localname(".db")
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end
	-- 踢掉之前的链接
	kickByUserid(userid)
	
	--local subid = skynet.call(dbserver, "lua", "db", "setAuth", userid, secret, 0, loginType)
	local key = string.format("user:%d", userid)
	local subid = math.random(1,999999)
	local res = skynet.call(dbserver, "lua", "dbRedis", "hset", key, "token", secret, "subid", subid)
	if res then
		return subid
	else
		return -1
	end
end

function CMD.showLogins()
	for k,v in pairs(logins) do
		log.info("wsgate showLogins: %d %d", k, v)
	end

	for k,v in pairs(connection) do
		log.info("wsgate connection: %d %d", k, v.userid or 0)
	end
end

function CMD.sendSvrMsg(source, userid, data)
	log.info("sendSvrMsg %d" ,userid)
	local fd = logins[userid]
	CMD.send(source, fd, data)
end

function handler.command(cmd, source, ...)
	local f = assert(CMD[cmd])
	return f(source, ...)
end

wsGateserver.start(handler)
