local skynet = require "skynet"
require "skynet.manager"
local name = "activity"
local CMD = {}

local function start()
    
end

function CMD.callFunc(moduleName, funcName, args)
    local modulePath = "activity." .. moduleName
    -- require异常处理
    local activityModule = nil
    local ok, err = pcall(function()
        activityModule = require(modulePath)
    end)
    if not ok then
        return {code = 0, result = "活动模块不存在"}
    end

    local func = activityModule[funcName]
    if not func then
        return {code = 0, result = "活动函数不存在"}
    end
    return func(args)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    skynet.register("." .. name)
    start()
end)