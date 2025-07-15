local skynet = require "skynet"
local wsGateserver = require "wsGateserver"
local websocket = require "http.websocket"
local urlTools = require "http.url"
local gConfig = CONFIG
local log = require "log"
local connection = {}	-- fd -> connection : { fd , client, agent , ip, mode } 链接池
local logins = {}	-- uid -> fd 登入池子

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

-- 登入认证
local function auth(data)
	local svrAuth = skynet.localname(".auth")
	if not svrAuth then
		return false
	end
	local res = skynet.call(svrAuth, "lua", "svrCall", "authGame", data)
	return res
end

local function connectGame(data)
	local svrGameManager = skynet.localname(".gameManager")
	if not svrGameManager then
		return false
	end
	local res = skynet.call(svrGameManager, "lua", "connectGame", tonumber(data.gameid), tonumber(data.roomid), tonumber(data.userid), tonumber(data.client_fd))
	return res
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
	local agent = c.agent
	if agent then
		--log.info("wsGameGate message forward")
		-- It's safe to redirect msg directly , gateserver framework will not free msg.
		skynet.redirect(agent, c.client, "client", fd, msg, string.len(msg))
	else
		log.info("wsGameGate message send")
		-- skynet.tostring will copy msg to a string, so we must free msg here.
		skynet.trash(msg,string.len(msg))
	end
end

function handler.connect(fd)
	log.info("wsGameGate connect")
end

function handler.handshake(fd, header, uri)
	local addr = websocket.addrinfo(fd)
	local ip = websocket.real_ip(fd)
	local data = urlTools.parse_query(uri)
	data.ip = ip or "0.0.0.0"
	data.uri = uri
	data.client_fd = fd
	log.info("wsGameGate handshake from: %s, uri %s, addr %s " ,tostring(fd), uri, addr)
	if auth(data) and connectGame(data) then
		log.info("wsGameGate handshake success")
		local c = {
			fd = fd,
			addr = addr,
			uri = uri,
			header = header,
			ip = ip,
			userid = data.userid,
			lastTime = skynet.time()
		}
		kickByUserid(data.userid)
		logins[data.userid] = fd
		connection[fd] = c
		wsGateserver.openclient(fd)
		-- todo 通知成功
	else
		wsGateserver.closeclient(fd)
	end
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
	log.info("wsGameGate ping")
	connection[fd].lastTime = skynet.time()
end

function handler.pong(fd)
	log.info("wsGameGate pong")
	connection[fd].lastTime = skynet.time()
end

local CMD = {}
function CMD.send(source, fd, msg)
	if not connection[fd] then
		log.info("wsgate send error: fd not found")
		return
	end
	websocket.write(fd, msg, "binary")
end
function handler.command(cmd, source, ...)
	local f = assert(CMD[cmd])
	return f(source, ...)
end

wsGateserver.start(handler, "wsGameGateserver")