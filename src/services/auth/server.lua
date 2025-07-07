local skynet = require "skynet"
require "skynet.manager"
local name = "auth"
local log = require "log"
local CMD = {}
local path = "auth."

local function start()
    
end

local function callFunc(moduleName, funcName, args)
    local serModule = nil
    local ok, err = pcall(function()
        serModule = require(path .. moduleName)
    end)
    if not ok then
        return 
    end
    local func = serModule[funcName]
    if not func then
        return 
    end

    return func(args)
end

function CMD.svrCall(funcName, args)
    local moduleName = "auth"
    return callFunc(moduleName, funcName, args)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    skynet.register("." .. name)
    start()
end)