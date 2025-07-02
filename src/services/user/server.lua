local skynet = require "skynet"
require "skynet.manager"
local name = "user"
local log = require "log"
local CMD = {}
local defaultModule = "user"

local function start()
    
end

function CMD.callFunc(moduleName, funcName, userid, args)
    if not moduleName or moduleName == "" then
        moduleName = defaultModule
    end

    local modulePath = "user." .. moduleName
    log.info("modulePath %s", modulePath)
    -- require异常处理
    local userModule = nil
    local ok, err = pcall(function()
        userModule = require(modulePath)
    end)
    if not ok then
        return {code = 0, result = "模块不存在"}
    end

    local func = userModule[funcName]
    if not func then
        return {code = 0, result = "函数不存在"}
    end
    return func(userid, args)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    skynet.register("." .. name)
    start()
end)