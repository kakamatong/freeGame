local skynet = require "skynet"
local log = require "log"
local CMD = {}
local defaultModule = "robot"
local path = "robot."

local function start()
    
end

local function callFunc(moduleName, funcName, args)
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

    return func(args)
end

function CMD.svrCall(moduleName, funcName, args)
    log.info("robot svrCall %s %s", moduleName, funcName)
    return callFunc(moduleName, funcName, args)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    
    start()
end)