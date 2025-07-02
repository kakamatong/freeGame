local skynet = require "skynet"
require "skynet.manager"
local name = "user"
local log = require "log"
local CMD = {}
local defaultModule = "user"
local path = "user."

local function start()
    
end

local function callFunc(moduleName, funcName, userid, args)
    local userModule = nil
    local ok, err = pcall(function()
        userModule = require(path .. moduleName)
    end)
    if not ok then
        return 
    end
    local func = userModule[funcName]
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
    if not clientInterfaces[moduleName][funcName] then
        return UTILS.result()
    end

    return UTILS.result(callFunc(moduleName, funcName, userid, args))
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    skynet.register("." .. name)
    start()
end)