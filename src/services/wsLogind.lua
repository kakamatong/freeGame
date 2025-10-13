-- wsLogind.lua
-- WebSocket 登录服务，负责处理用户登录、认证和网关注册
local login = require "wsLoginserver"
local crypt = require "skynet.crypt"
local skynet = require "skynet"
local log = require "log"
local md5 =	require	"md5"
local cluster = require "skynet.cluster"
local gConfig = CONFIG
-- 服务器配置信息
local server = {
	host = skynet.getenv("loginAddress"),           -- 监听地址
	port = skynet.getenv("loginPort"),                -- 监听端口
	multilogin = false,         -- 是否允许多端登录
	name = CONFIG.SVR_NAME.LOGIN,  -- 服务名
	protocol = skynet.getenv("protocol"), -- 协议
}

local server_list = {}    -- 注册的网关服务器列表
local login_type = {
	account = true,           -- 允许的登录类型
	wechatMiniGame = true,		-- 微信小游戏
}
local bRegister = false
local register = "register"

local function pushLog(username, ip, loginType, status, ext)
	local dbserver = skynet.localname(CONFIG.SVR_NAME.DB)
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end
	skynet.send(dbserver, "lua", "dbLog", "insertLoginLog", username, ip, loginType, status, ext)
end

local function registerUser(user, password, loginType, server, ip)
	local dbserver = skynet.localname(CONFIG.SVR_NAME.DB)
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end
	local userid = skynet.call(dbserver, "lua", "db", "registerUser",loginType)
	pushLog(userid, ip or "0.0.0.0", loginType, 2, '')
	return server, userid, loginType
end

-- 认证处理函数，校验token并返回用户信息
-- 1. 账户表根据登入类型不同有多张，记录了每个登入类型（account,wechatMiniGame）的登入名，对应的userid，玩家登入的时候，
--    会来这张表核对用户名和密码，然后返回对应的userid，如果userid为0，或者不存在，表示注册新账号
-- 2. 新账号分配，根据auth表自增字段userid为准，分配userid后，会设置userData默认值，并更新账户表的userid(之前为0的情况)
function server.login_handler(token, ip)
	-- token格式：base64(user)@base64(server):base64(password)#base64(loginType)
	local user, server, password, loginType = token:match("([^@]+)@([^:]+):([^#]+)#(.+)")
	user = crypt.base64decode(user)
	server = crypt.base64decode(server)
	password = crypt.base64decode(password)
	loginType = crypt.base64decode(loginType)
	log.info(string.format("user %s login, server is %s, loginType is %s", user, server, loginType))

	local dbserver = skynet.localname(CONFIG.SVR_NAME.DB)
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end
	local userInfo = skynet.call(dbserver, "lua", "db", "getLoginInfo", user,loginType)
	-- 注册用户
	if bRegister and string.find(loginType, register) then
		assert(not userInfo, "user already exists")
		local infos = UTILS.string_split(loginType, "|")
		assert(login_type[infos[2]], "register user error")
		return registerUser(user, password, infos[2],server, ip)
	end

	assert(login_type[loginType])
	if not userInfo or userInfo.userid == 0 then
		local server, userid, loginType = registerUser(user, password, loginType,server, ip)
		if not userInfo then
			skynet.call(dbserver, "lua", "db", "insertUserLogin", userid, user, password, loginType)
		end
		if userInfo.userid == 0 then
			skynet.call(dbserver, "lua", "db", "updateUserLogin", userid, user, loginType)
		end
		return server, userid, loginType
	else
		local spePassword = string.upper(md5.sumhexa(password))
		log.info("spePassword is " .. spePassword)
		local status = 0
		if spePassword == userInfo.password then
			status = 1
		end
		pushLog(user, ip or "0.0.0.0", loginType, status, token)
		assert(status == 1, "account or password error")
	end

	-- 校验用户名和密码
	--local userInfo = skynet.call(dbserver, "lua", "func", "login", user,password,loginType)
	-- 抛送日志
	return server, userInfo.userid, loginType
end

-- 登录处理函数，分配subid
function server.login_after_handler(server, userid, secret, loginType)
	log.info(string.format("%d@%s is login, secret is %s", userid, server, crypt.hexencode(secret)))
	local clusterManager = skynet.localname(CONFIG.SVR_NAME.CLUSTER)
	local check = skynet.call(clusterManager, "lua", "checkHaveNode", server)
	assert(check, "gameserver not started")
	-- 只允许一个用户在线
	-- local last = user_online[numid]
	-- if last then
	-- 	skynet.call(last.address, "lua", "kickByNumid", numid, last.subid)
	-- end
	-- if user_online[numid] then
	-- 	error(string.format("user %d is already online", numid))
	-- end
	log.info("login server is %s", server)
	local subid = tostring(callTo(server, "gate1","login", userid, crypt.hexencode(secret), loginType))
	-- user_online[numid] = { address = gameserver, subid = subid , secret = crypt.hexencode(secret)}
	return subid, server
end

local CMD = {}

-- 注册网关服务器
function CMD.register_gate(server, address)
	log.info(string.format("Register gate %s %s", server, address))
	server_list[server] = address
end

-- function CMD.logout(uid, subid)
-- 	local u = user_online[uid]
-- 	if u then
-- 		print(string.format("%s@%s is logout", uid, u.server))
-- 		user_online[uid] = nil
-- 	end
-- end

-- 命令分发处理
function server.command_handler(command, ...)
	local f = assert(CMD[command])
	return f(...)
end

-- 启动WebSocket登录服务
login(server)
