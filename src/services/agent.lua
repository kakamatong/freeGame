-- agent.lua
-- 玩家代理服务，负责与客户端通信、处理玩家请求、心跳、状态和匹配等
local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local log = require "log"
local cjson = require "cjson"
local WATCHDOG
local gate
local host
local CMD = {}
local REQUEST = {}
local client_fd
local userid = 0
local svrUser = nil
local svrMatch = nil

-- 发送数据包给客户端
local function send_package(pack)
	skynet.call(gate, "lua", "send", client_fd, pack)
end

function REQUEST:userData(args)
	return call(svrUser, "userData", args.userid)
end

function REQUEST:userRiches(args)
	local richType, richNums = call(svrUser, "userRiches", userid)
	return {
		richType = richType,
		richNums = richNums,
	}
end

function REQUEST:userStatus(args)
	return call(svrUser, "userStatus", userid)
end

function REQUEST:matchJoin(args)
	return call(svrMatch, "matchJoin", userid, args.gameid, args.queueid)
end

function REQUEST:matchLeave(args)
	return call(svrMatch, "matchLeave", userid, args.gameid, args.queueid)
end

function REQUEST:matchOnSure(args)
	return call(svrMatch, "matchOnSure", userid, args.id, args.sure)
end

-- 客户端请求分发
local function request(name, args, response)
	assert(REQUEST[name])
	local r = REQUEST[name](REQUEST, args)
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
-- 启动agent服务，初始化协议和心跳检测
function CMD.start(conf)
	local fd = conf.client
	gate = conf.gate
	WATCHDOG = conf.watchdog
	client_fd = fd
	userid =conf.userid
	-- slot 1,2 set at main.lua
	host = sprotoloader.load(1):host "package"

	svrUser = skynet.uniqueservice(CONFIG.SVR_NAME.USER)
	svrMatch = skynet.uniqueservice(CONFIG.SVR_NAME.MATCH)
	skynet.send(gate, "lua", "forward", fd, skynet.self())
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
