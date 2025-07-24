local skynet = require "skynet"
local log = require "log"
local CMD = {}
local defaultModule = "user"
local path = "user."

local function start()
    
end

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
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)
    start()
end)