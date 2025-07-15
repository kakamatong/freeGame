-- agent.lua
-- 玩家代理服务，负责与客户端通信、处理玩家请求、心跳、状态和匹配等
local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local log = require "log"
local cjson = require "cjson"
local WATCHDOG
local gate
local host
local send_request
local CMD = {}
local REQUEST = {}
local client_fd
local leftTime = 0
local dTime = 15 -- 心跳时间（秒）
local userid = 0
local reportsessionid = 0
local gameid = 0
local roomid = 0


-- 发送数据包给客户端
local function send_package(pack)
	skynet.call(gate, "lua", "send", client_fd, pack)
end

-- 上报玩家状态或消息给客户端
local function report(name, data)
	reportsessionid = reportsessionid + 1
	send_request = host:attach(sprotoloader.load(2))
	send_package(send_request(name,data, reportsessionid))
end

local function sendSvrMsg(typeName, data)
	report("svrMsg", {type = typeName, data = data})
end

-- 关闭连接
local function close()
	log.info("agent close")
	skynet.call(gate, "lua", "kick", client_fd)
end

-- region 以下为客户端请求处理函数（REQUEST表）
------------------------------------------------------------------------------------------------------------
-- 心跳包处理，刷新活跃时间
function REQUEST:heartbeat()
	--log.info("heartbeat")
	leftTime = os.time()
	local data = {
		type = "heartbeat",
		timestamp = leftTime
	}
	
	return { code =1, result = cjson.encode(data) }
end

-- 客户端主动退出
function REQUEST:quit()
	skynet.call(WATCHDOG, "lua", "close", client_fd)
end

-- 连接游戏
function REQUEST:connectGame(args)
	local gameServer = skynet.localname(".gameManager")
	if not gameServer then
		log.error("gameManager not started")
		return
	else
		local ret = skynet.call(gameServer, "lua", "connectGame", gameid, roomid, userid, client_fd, skynet.self())
		if ret then
			return {code = 0, msg = "链接游戏成功"}
		else
			return {code = 1, msg = "链接游戏失败"}
		end
	end
end

local function clientCall(serverName, moduleName, funcName, args)
	if serverName == "agent" then
		local f = assert(REQUEST[funcName])
		return f(REQUEST, args)
	else
		local server = skynet.localname("." .. serverName)
		if not server then
			local msg = "找不到服务"
			log.error(msg .. serverName)
			return {code = 0, result = msg}
		end
		return skynet.call(server, "lua", "clientCall", moduleName, funcName, userid, args)
	end
end

-- 客户端请求分发
local function request(name, args, response)
	--log.info("request %s", name)
	local r = clientCall(args.serverName, args.moduleName, args.funcName, cjson.decode(args.args))
	if response then
		return response(r)
	end
end

-- 注册客户端协议，处理客户端消息
skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		--log.info("agent unpack msg %s, sz %d", type(msg), sz)
		local str = skynet.tostring(msg, sz)
		return host:dispatch(str, sz)
	end,
	dispatch = function (fd, _, type, ...)
		--log.info("agent dispatch fd %d, type %s", fd, type)
		assert(fd == client_fd) -- 只能处理自己的fd
		skynet.ignoreret() -- session是fd，不需要返回
		if type == "REQUEST" then
			local ok, result  = pcall(request, ...)
			if ok then
				if result then
					send_package(result)
				end
			else
				log.error(result)
			end
		else
			assert(type == "RESPONSE")
			error "This example doesn't support request client"
		end
	end
}

-- 服务准备就绪
local function svrReady()
	log.info("agent content")
	report("svrReady",{code = 1})
end
------------------------------------------------------------------------------------------------------------

-- region CMD表：服务内部命令处理
------------------------------------------------------------------------------------------------------------
-- 启动agent服务，初始化协议和心跳检测
function CMD.start(conf)
	local fd = conf.client
	gate = conf.gate
	WATCHDOG = conf.watchdog
	client_fd = fd
	userid =conf.userid
	-- slot 1,2 set at main.lua
	host = sprotoloader.load(1):host "package"
	leftTime = os.time()
	-- 启动心跳检测协程
	-- skynet.fork(function()
	-- 	while true do
	-- 		local now = os.time()
	-- 		if now - leftTime >= dTime then
	-- 			log.info("agent heartbeat fd %d now %d leftTime %d", client_fd, now, leftTime)
	-- 			close()
	-- 			break
	-- 		end
	-- 		skynet.sleep(dTime * 100)
	-- 	end
	-- end)
	skynet.send(gate, "lua", "forward", fd, skynet.self())
	--svrReady()
end

-- 断开连接，清理状态
function CMD.disconnect()
	log.info("agent disconnect")
	skynet.exit()
end
------------------------------------------------------------------------------------------------------------

-- 启动服务，分发命令
skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		local f = CMD[command]
		if f then
			skynet.ret(skynet.pack(f(...)))
		end
	end)
end)
