-- match.lua
-- 匹配服务，负责玩家匹配逻辑和队列管理
local skynet = require "skynet"
local log = require "log"
local CMD = {}
local dTime = 1          -- 匹配检查间隔（秒）
local defaultModule = "match"
local path = "match."
local dbSvr = nil

-- 启动匹配服务，定时检查所有队列
function start()
    log.info("match start")
    skynet.fork(function()
        while true do
            local match = require(path .. "match")
            match.tick()
            skynet.sleep(dTime * 100)
        end
    end)
end

-----------------------------------------------------------------------------------------

local function callFunc(moduleName, funcName, userid, args)
    local svrModule = nil
    local ok, err = pcall(function()
        svrModule = require(path .. moduleName)
    end)
    if not ok or not svrModule then
        return 
    end
    local func = svrModule[funcName]
    if not func then
        return 
    end

    return func(userid, args)
end

function CMD.svrCall(moduleName, funcName, userid, args)
    return callFunc(moduleName, funcName, userid, args)
end

function CMD.clientCall(moduleName, funcName, userid, args)
    if not moduleName or moduleName == "" then
        moduleName = defaultModule
    end

    local clientInterfaces = require(path .. "clientInterfaces")
    if not clientInterfaces or not clientInterfaces[moduleName] or not clientInterfaces[moduleName][funcName] then
        return UTILS.result()
    end

    return UTILS.result(callFunc(moduleName, funcName, userid, args))
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		--skynet.trace()
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
    

    start()
end)