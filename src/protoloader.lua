-- protoloader.lua
-- 协议加载服务，负责注册客户端和服务端通信协议
local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local log = require "log"

skynet.start(function()
	-- 注册客户端到服务端协议（1号）
	sprotoloader.register("proto/lobby/c2s.sproto", 1)
	-- 注册服务端到客户端协议（2号）
	sprotoloader.register("proto/lobby/s2c.sproto", 2)
	log.info("protoloader start")
	-- 注意：不要调用skynet.exit()，否则协议模块会被卸载，导致全局协议失效
end)

