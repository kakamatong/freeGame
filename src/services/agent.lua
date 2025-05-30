-- agent.lua
-- 玩家代理服务，负责与客户端通信、处理玩家请求、心跳、状态和匹配等
local skynet = require "skynet"
local websocket = require "http.websocket"
local sproto = require "sproto"
local sprotoloader = require "sprotoloader"

local WATCHDOG
local gate
local host
local send_request

local CMD = {}
local REQUEST = {}
local client_fd
local leftTime = 0
local dTime = 15 -- 心跳时间（秒）
local bAuth = false -- 是否已认证
local userid = 0
local userStatus = 0
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

-- 关闭连接
local function close()
	LOG.info("agent close")
	skynet.call(gate, "lua", "kick", client_fd)
	--skynet.exit()
end

-- 获取数据库服务句柄
local function getDB()
	local dbserver = skynet.localname(".dbserver")
	if not dbserver then
		LOG.error("wsgate login error: dbserver not started")
		return
	end
	return dbserver
end

-- 设置用户状态到数据库
local function setUserStatus(status, gameid, roomid)
	if not status then return end
	userStatus = status
	local db = getDB()
	skynet.call(db, "lua", "func", "setUserStatus", userid, status, gameid, roomid)
end

-- 检查并同步用户状态
local function checkStatus()
	local db = getDB()
	local status = skynet.call(db, "lua", "func", "getUserStatus", userid)
	if not status or status.gameid == 0 then
		setUserStatus(CONFIG.USER_STATUS.ONLINE)
		return
	elseif status.gameid > 0 then
		gameid = status.gameid
		roomid = status.roomid
		setUserStatus(CONFIG.USER_STATUS.GAMEING)
		return
	end
end

-- 发送请求到游戏服务
local function sendToGame(name, args, response)
	if args.gameid ~=gameid or args.roomid ~=roomid then
		LOG.error("游戏id或房间id不匹配 %d %d %d %d", args.gameid, gameid, args.roomid, roomid)
		return
	end
	local gameServer = skynet.localname(".gameManager")
	if not gameServer then
		LOG.error("gameManager not started")
		return
	else
		skynet.send(gameServer, "lua", "onClinetMsg", userid, name, args, response)
	end
end

-- 进入匹配队列
local function enterMatch(args)
	if userStatus == CONFIG.USER_STATUS.MATCHING then
		return {code = 2, msg ="已经在匹配队列中"}
	end

	if userStatus == CONFIG.USER_STATUS.GAMEING then
		return {code = 2, msg ="已经在游戏中"}
	end

	local matchServer = skynet.localname(".match")
	if not matchServer then
		return {code = 1, msg ="匹配服务异常"}
	else
		local b = skynet.call(matchServer, "lua", "enterQueue", skynet.self(), userid, args.gameid, args.gameSubid, 0)
		if b then
			setUserStatus(CONFIG.USER_STATUS.MATCHING)
			report("reportUserStatus", {status = CONFIG.USER_STATUS.MATCHING})
			return {code = 0, msg ="进入匹配列队成功"}
		else
			return {code = 2, msg ="进入匹配列队失败"}
		end
	end
end

-- 离开匹配队列
local function leaveMatch()
	local matchServer = skynet.localname(".match")
	if not matchServer then
		return {code = 1, msg ="匹配服务异常"}
	else
		local b = skynet.call(matchServer, "lua", "leaveQueue", userid)
		if b then
			setUserStatus(CONFIG.USER_STATUS.ONLINE)
			report("reportUserStatus", {status = CONFIG.USER_STATUS.ONLINE})
			return {code = 0, msg ="离开匹配列队成功"}
		else
			return {code = 2, msg ="离开匹配列队失败"}
		end
	end
end

-- 以下为客户端请求处理函数（REQUEST表）
function REQUEST:get()
	print("get", self.what)
	local r = skynet.call("SIMPLEDB", "lua", "get", self.what)
	return { result = r }
end

function REQUEST:set()
	print("set", self.what, self.value)
	skynet.call("SIMPLEDB", "lua", "set", self.what, self.value)
end

-- 心跳包处理，刷新活跃时间
function REQUEST:heartbeat()
	leftTime = os.time()
	return { timestamp = leftTime }
end

-- 客户端主动退出
function REQUEST:quit()
	skynet.call(WATCHDOG, "lua", "close", client_fd)
end

-- 获取用户详细数据
function REQUEST:userData(args)
	local db = getDB()
	local userData = skynet.call(db, "lua", "func", "getUserData", userid)
	assert(userData)
	return userData
end

-- 获取用户财富信息
function REQUEST:userRiches(args)
	local db = getDB()
	local userRiches = skynet.call(db, "lua", "func", "getUserRiches", userid)
	assert(userRiches)
	local richType = {}
	local richNums = {}
	for k,v in pairs(userRiches) do
		table.insert(richType, v.richType)
		table.insert(richNums, v.richNums)
	end
	LOG.info("richType %s", UTILS.tableToString(richType))
	LOG.info("richNums %s", UTILS.tableToString(richNums))
	return {richType = richType, richNums = richNums}
end

-- 获取用户状态
function REQUEST:userStatus(args)
	local db = getDB()
	local status = skynet.call(db, "lua", "func", "getUserStatus", userid)
	if not status then
		return {gameid = 0 , status = -1}
	else
		return {gameid = status.gameid , status=status.status, roomid = status.roomid}
	end
end

-- 匹配请求处理
function REQUEST:match(args)
	if args.type == 0 then
		return enterMatch(args)
	else
		return leaveMatch(args)
	end
end

-- 认证请求处理
function REQUEST:auth(args)
	LOG.info("auth username %s, password %s", args.userid, args.password)
	local db =getDB()
	local authInfo = skynet.call(db, "lua", "func", "getAuth", args.userid)
	if not authInfo then
		return {code = 1, msg = "acc failed"}
	end
	if authInfo.secret ~= args.password then
		return {code = 2, msg = "pass failed"}
	end
	if authInfo.subid ~= args.subid then
		return {code = 3, msg = "subid failed"}
	end
	skynet.call(db, "lua", "func", "addSubid", args.userid, authInfo.subid + 1)
	bAuth = true
	userid = args.userid
	leftTime = os.time()
	checkStatus()
	return {code = 0, msg = "success"}
end

-- 连接游戏
function REQUEST:connectGame(args)
	local gameServer = skynet.localname(".gameManager")
	if not gameServer then
		LOG.error("gameManager not started")
		return
	else
		local ret = skynet.call(gameServer, "lua", "connectGame", gameid, roomid, userid, client_fd)
		if ret then
			return {code = 0, msg = "链接游戏成功"}
		else
			return {code = 1, msg = "链接游戏失败"}
		end
	end
end

-- 客户端请求分发
local function request(name, args, response)
	LOG.info("request %s", name)
	if not bAuth and name ~= "auth" then
		return 
	end
	if args.roomid  and args.roomid > 0 then
		sendToGame(name, args, response)
		return
	end
	local f = assert(REQUEST[name])
	local r = f(REQUEST, args)
	if response then
		return response(r)
	end
end

-- 注册客户端协议，处理客户端消息
skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		--LOG.info("agent unpack msg %s, sz %d", type(msg), sz)
		local str = skynet.tostring(msg, sz)
		return host:dispatch(str, sz)
	end,
	dispatch = function (fd, _, type, ...)
		--LOG.info("agent dispatch fd %d, type %s", fd, type)
		assert(fd == client_fd) -- 只能处理自己的fd
		skynet.ignoreret() -- session是fd，不需要返回
		if type == "REQUEST" then
			local ok, result  = pcall(request, ...)
			if ok then
				if result then
					send_package(result)
				end
			else
				LOG.error(result)
			end
		else
			assert(type == "RESPONSE")
			error "This example doesn't support request client"
		end
	end
}

-- CMD表：服务内部命令处理
-- 进入游戏
function CMD.enterGame(gamedata)
	gameid = gamedata.gameid
	roomid = gamedata.roomid
	local gameServer = skynet.localname(".gameManager")
	if not gameServer then
		LOG.error("gameManager not started")
		return
	else
		skynet.call(gameServer, "lua", "plyaerEnter", gameid, roomid, {userid = userid})
	end

	report("reportMatch", {code = 0, msg = "匹配成功", gameid = gameid, roomid = roomid})
	
	setUserStatus(CONFIG.USER_STATUS.GAMEING, gameid, roomid)
	report("reportUserStatus", {status = CONFIG.USER_STATUS.GAMEING, gameid = gameid, roomid = roomid})
end

-- 内容推送
function CMD.content()
	LOG.info("agent content")
	report("reportContent",{code = 1})
end

-- 启动agent服务，初始化协议和心跳检测
function CMD.start(conf)
	local fd = conf.client
	gate = conf.gate
	WATCHDOG = conf.watchdog
	client_fd = fd
	-- slot 1,2 set at main.lua
	host = sprotoloader.load(1):host "package"
	leftTime = os.time()
	-- 启动心跳检测协程
	skynet.fork(function()
		while true do
			local now = os.time()
			if now - leftTime >= dTime then
				LOG.info("agent heartbeat fd %d now %d leftTime %d", client_fd, now, leftTime)
				close()
				break
			end
			skynet.sleep(dTime * 100)
		end
	end)
	skynet.call(gate, "lua", "forward", fd, fd, skynet.self())
end

-- 断开连接，清理状态
function CMD.disconnect()
	if userStatus == CONFIG.USER_STATUS.MATCHING then
		local matchServer = skynet.localname(".match")
		skynet.send(matchServer, "lua", "leaveQueue", userid)
	end
	setUserStatus(CONFIG.USER_STATUS.OFFLINE)
	LOG.info("agent disconnect")
	skynet.exit()
end

-- 启动服务，分发命令
skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		local f = CMD[command]
		if f then
			skynet.ret(skynet.pack(f(...)))
		end
	end)
end)
