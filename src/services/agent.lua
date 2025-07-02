-- agent.lua
-- 玩家代理服务，负责与客户端通信、处理玩家请求、心跳、状态和匹配等
local skynet = require "skynet"
local websocket = require "http.websocket"
local sproto = require "sproto"
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
local bAuth = false -- 是否已认证
local userid = 0
local userStatus = 0
local reportsessionid = 0
local gameid = 0
local roomid = 0
local userData = nil
local addr = ''
local ip ="0.0.0.0"
local loginChannel = ""
local gConfig = CONFIG

local function pushLog(userid, nickname, ip, loginType, status, ext)
	local dbserver = skynet.localname(".db")
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end
	skynet.send(dbserver, "lua", "dbLog", "insertLoginLog", userid, nickname, ip, loginType, status, ext)
end

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
	log.info("agent close")
	skynet.call(gate, "lua", "kick", client_fd)
	--skynet.exit()
end

-- 获取数据库服务句柄
local function getDB()
	local dbserver = skynet.localname(".db")
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end
	return dbserver
end

-- 设置用户状态到数据库
local function setUserStatus(status, gameid, roomid)
	if not status then return end
	userStatus = status
	local db = getDB()
	skynet.call(db, "lua", "db", "setUserStatus", userid, status, gameid, roomid)
end

local function checkInGame(tmpGameid, tmpRoomid)
	local gameServer = skynet.localname(".gameManager")
	if not gameServer then
		log.error("gameManager not started")
		return
	end

	local b = skynet.call(gameServer, "lua", "checkHaveRoom", tmpGameid, tmpRoomid)
	if not b then
		log.error("game not found %d %d", tmpGameid, tmpRoomid)
		return
	end

	return true
end

-- 检查并同步用户状态
local function checkStatus()
	local db = getDB()
	local status = skynet.call(db, "lua", "db", "getUserStatus", userid)
	if not status or status.gameid == 0 then
		setUserStatus(gConfig.USER_STATUS.ONLINE)
		return
	elseif status.gameid > 0 then
		-- 检查房间是否存在,不存在则直接设置为在线
		
		local b = checkInGame(status.gameid, status.roomid)
		if not b then
			setUserStatus(gConfig.USER_STATUS.ONLINE)
			return
		end

		gameid = status.gameid
		roomid = status.roomid

		setUserStatus(gConfig.USER_STATUS.GAMEING)
		return
	end
end

-- 发送请求到游戏服务
local function sendToGame(name, args, response)
	if args.gameid ~=gameid or args.roomid ~=roomid then
		log.error("游戏id或房间id不匹配 %d %d %d %d", args.gameid, gameid, args.roomid, roomid)
		return
	end
	local gameServer = skynet.localname(".gameManager")
	if not gameServer then
		log.error("gameManager not started")
		return
	else
		skynet.send(gameServer, "lua", "onClinetMsg", userid, name, args)
	end
end

-- 进入匹配队列
local function enterMatch(args)
	-- if userStatus == gConfig.USER_STATUS.MATCHING then
	-- 	return {code = 2, msg ="已经在匹配队列中"}
	-- end

	if userStatus == gConfig.USER_STATUS.GAMEING and checkInGame(gameid, roomid) then
		return {code = 3, msg ="已经在游戏中", gameid = gameid, roomid = roomid}
	end

	local matchServer = skynet.localname(".match")
	if not matchServer then
		return {code = 1, msg ="匹配服务异常"}
	else
		local b = skynet.call(matchServer, "lua", "enterQueue", skynet.self(), userid, args.gameid, args.gameSubid, 0)
		if b then
			setUserStatus(gConfig.USER_STATUS.MATCHING)
			report("reportUserStatus", {status = gConfig.USER_STATUS.MATCHING})
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
			setUserStatus(gConfig.USER_STATUS.ONLINE)
			report("reportUserStatus", {status = gConfig.USER_STATUS.ONLINE})
			return {code = 0, msg ="离开匹配列队成功"}
		else
			return {code = 2, msg ="离开匹配列队失败"}
		end
	end
end

-- 获取用户数据
local function getUserData()
	local db = getDB()
	userData = skynet.call(db, "lua", "db", "getUserData", userid)
	return userData
end

-- 获取用户财富信息
local function getUserRiches()
	local db = getDB()
	local userRiches = skynet.call(db, "lua", "db", "getUserRiches", userid)
	if not userRiches then
		return {}, {}
	end
	local richType = {}
	local richNums = {}
	for k,v in pairs(userRiches) do
		table.insert(richType, v.richType)
		table.insert(richNums, v.richNums)
	end
	return richType, richNums
end

-- 获取用户财富信息，根据类型获取
local function getUserRichesByType(richType)
	local db = getDB()
	local userRiches = skynet.call(db, "lua", "db", "getUserRichesByType", userid, richType)
	if not userRiches then
		return 0
	end

	return userRiches.richNums
end

-- test
local function test()
	-- local db = getDB()
	-- local userRiches = skynet.call(db, "lua", "db", "addUserRiches", userid, 2, 10000)
	-- assert(userRiches)
	local db = getDB()
	local userData = skynet.call(db, "lua", "dbRedis", "test")
end

-- region 以下为客户端请求处理函数（REQUEST表）
------------------------------------------------------------------------------------------------------------
-- 心跳包处理，刷新活跃时间
function REQUEST:heartbeat()
	leftTime = os.time()
	return { timestamp = leftTime }
end

-- 客户端主动退出
function REQUEST:quit()
	skynet.call(WATCHDOG, "lua", "close", client_fd)
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
function REQUEST:login(args)
	log.info("login username %s, password %s", args.userid, args.password)
	local db =getDB()
	local authInfo = skynet.call(db, "lua", "db", "getAuth", args.userid)
	if not authInfo then
		pushLog(args.userid, '', ip, args.channel, 0, 'acc failed')
		return {code = 1, msg = "acc failed"}
	end

	if authInfo.secret ~= args.password then
		pushLog(args.userid, '', ip, args.channel, 0, 'pass failed')
		return {code = 2, msg = "pass failed"}
	end

	log.info("authInfo.subid %s, args.subid %s", authInfo.subid, args.subid)
	if authInfo.subid ~= args.subid then
		pushLog(args.userid, '', ip, args.channel, 0, 'subid failed')
		return {code = 3, msg = "subid failed"}
	end
	pushLog(args.userid, '', ip, args.channel, 1, 'success')

	-- 通知gate登录成功
	skynet.call(gate, "lua", "loginSuccess", args.userid, client_fd)
	skynet.call(db, "lua", "db", "addSubid", args.userid, authInfo.subid + 1)
	bAuth = true
	userid = args.userid
	loginChannel = args.channel or ""
	leftTime = os.time()

	checkStatus()
	return {code = 0, msg = "success"}
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

local function call(serverName, moduleName, funcName, args)
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
		skynet.call(server, "lua", "callFunc", moduleName, funcName, args)
	end
end

-- 客户端请求分发
local function request(name, args, response)
	--log.info("request %s", name)
	if not bAuth and not (args.funcName == "login" and args.serverName == "agent") then
		return 
	end

	local r = call(args.serverName, args.moduleName, args.funcName, cjson.decode(args.args))
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
------------------------------------------------------------------------------------------------------------

-- region CMD表：服务内部命令处理
------------------------------------------------------------------------------------------------------------
-- 进入游戏
function CMD.enterGame(gamedata)
	gameid = gamedata.gameid
	roomid = gamedata.roomid
	local gameServer = skynet.localname(".gameManager")
	if not gameServer then
		log.error("gameManager not started")
		return
	else
		skynet.call(gameServer, "lua", "playerEnter", gameid, roomid, userData)
	end

	report("reportMatch", {code = 0, msg = "匹配成功", gameid = gameid, roomid = roomid})
	
	setUserStatus(gConfig.USER_STATUS.GAMEING, gameid, roomid)
	report("reportUserStatus", {status = gConfig.USER_STATUS.GAMEING, gameid = gameid, roomid = roomid})
end

function CMD.onReport(data)
	-- 财富变更信息
	if data.type == 1 then
		local richTypes = data.richTypes
		local richNums = data.richNums
		local allRichNums = {}
		for i = 1, #richTypes do
			local richType = richTypes[i]
			local richNum = getUserRichesByType(richType)
			table.insert(allRichNums, richNum)
		end

		-- todo: 下发财富变更信息
		report("reportUpdateRich", {richTypes = richTypes, richNums = richNums, richAllNums = allRichNums, ext = ""})
	end
end

function CMD.leaveGame()
	log.info("leaveGame")
	gameid = 0
	roomid = 0
	setUserStatus(gConfig.USER_STATUS.ONLINE, gameid, roomid)
	report("reportUserStatus", {status = gConfig.USER_STATUS.ONLINE, gameid = gameid, roomid = roomid})
end

-- 内容推送
function CMD.content()
	log.info("agent content")
	report("reportContent",{code = 1})
end

-- 启动agent服务，初始化协议和心跳检测
function CMD.start(conf)
	local fd = conf.client
	gate = conf.gate
	WATCHDOG = conf.watchdog
	client_fd = fd
	addr = conf.addr
	if conf.ip then
		ip = conf.ip
	end
	-- slot 1,2 set at main.lua
	host = sprotoloader.load(1):host "package"
	leftTime = os.time()
	-- 启动心跳检测协程
	skynet.fork(function()
		while true do
			local now = os.time()
			if now - leftTime >= dTime then
				log.info("agent heartbeat fd %d now %d leftTime %d", client_fd, now, leftTime)
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
	if userStatus == gConfig.USER_STATUS.MATCHING then
		local matchServer = skynet.localname(".match")
		skynet.send(matchServer, "lua", "leaveQueue", userid)
	elseif userStatus == gConfig.USER_STATUS.GAMEING then
		local gameServer = skynet.localname(".gameManager")
		skynet.send(gameServer, "lua", "offLine", gameid, roomid, userid)
	end
	setUserStatus(gConfig.USER_STATUS.OFFLINE)
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
