local skynet = require "skynet"
local wsGateserver = require "wsGateserver"
local websocket = require "http.websocket"
local urlTools = require "http.url"
local cluster = require "skynet.cluster"
local log = require "log"
local connection = {}	-- fd -> connection : { fd , client, agent , ip, mode } 链接池
local logins = {}	-- uid -> fd 登入池子
skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
}
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

local function close_fd(fd)
	local c = connection[fd]
	if c then
		if c.room then
			skynet.send(c.room, "lua", "socketClose", fd)
		end
		clearLogin(c)
		unforward(c)
		connection[fd] = nil
	end
end

local function kickByUserid(userid)
	local fd = logins[userid]
	if fd then
		wsGateserver.closeclient(fd)
	end
end

local function getRoom(gameid, roomid)
	local svrGameManager = skynet.localname(CONFIG.SVR_NAME.GAMES)
	if not svrGameManager then
		return false
	end

	local res = skynet.call(svrGameManager, "lua", "getGame", gameid, roomid)
	return res
end

-- 登入认证
local function auth(data)
	return call(CONFIG.CLUSTER_SVR_NAME.AUTH, "authGame", data)
end

local function connectGame(data)
	local svrGameManager = skynet.localname(CONFIG.SVR_NAME.GAMES)
	if not svrGameManager then
		return false
	end

	local gameid = tonumber(data.gameid)
	local roomid = tonumber(data.roomid)
	local userid = tonumber(data.userid)
	local client_fd = tonumber(data.client_fd)

	return skynet.call(svrGameManager, "lua", "connectGame", userid, gameid, roomid, client_fd)
end

local function startCheckAlive()
	skynet.fork(function ()
		while true do
			skynet.sleep(1000) -- 10s
			local now = skynet.time()
			for fd, c in pairs(connection) do
				if now - c.lastTime > 15 then
					log.info("wsGameGate checkAlive")
					websocket.close(fd)
				else
					websocket.ping(fd)
				end
			end
		end
	end)
end

local handler = {}

function handler.open(source, conf)
	log.info("wsGameGate open")

	startCheckAlive()
	return conf.address, conf.port
end

function handler.message(fd, msg, msgType)
	--log.info("wsGameGate message")
	-- recv a package, forward it
	local c = connection[fd]
	if c and c.room then
		skynet.redirect(c.room, fd, "client", fd, msg, string.len(msg))
	else
		skynet.trash(msg,string.len(msg))
	end
end

function handler.connect(fd)
	log.info("wsGameGate connect")
end

function handler.auth(fd, uri, addr)
	log.info("wsgate auth %d, %s", fd, uri)
	local data = urlTools.parse_query(uri)
	data.ip = addr or "0.0.0.0"
	data.uri = uri
	data.client_fd = fd
	local userid = tonumber(data.userid)
	-- 不能先去认证玩家，如果玩家认证通过了，但是房间认证没通过，会导致subid+1，从而影响下一次认证
	return connectGame(data) and auth(data),userid
end

function handler.authSuccess(fd, options, protocol,addr)
	local data = urlTools.parse_query(options.upgrade.url)
	local room = getRoom(tonumber(data.gameid), tonumber(data.roomid))
	local c = {
		fd = fd,
		userid = options.userid,
		addr = addr,
		protocol = protocol,
		room = room,
		lastTime = skynet.time()
	}

	kickByUserid(options.userid)
	logins[options.userid] = fd
	connection[fd] = c

	wsGateserver.openclient(fd, handler, protocol, addr, options)
end

function handler.handshake(fd, header, uri)
end

function handler.close(fd)
	log.info("wsGameGate close")
	close_fd(fd)
end

function handler.error(fd, msg)
	log.info("wsGameGate error")
	close_fd(fd)
end

function handler.ping(fd)
	--log.info("wsGameGate ping")
	connection[fd].lastTime = skynet.time()
end

function handler.pong(fd)
	--log.info("wsGameGate pong")
	connection[fd].lastTime = skynet.time()
end

local CMD = {}

function CMD.send(source, fd, msg)
	if not connection[fd] then
		log.info("wsgate send error: fd not found %d", fd)
		return
	end
	websocket.write(fd, msg, "binary")
end

function CMD.roomOver(source, fd)
	websocket.close(fd)
end

function handler.command(cmd, source, ...)
	local f = assert(CMD[cmd])
	return f(source, ...)
end

wsGateserver.start(handler, CONFIG.SVR_NAME.GAME_GATE)
