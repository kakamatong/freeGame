local skynet = require "skynet"
require "skynet.manager"
local name = "daySignIn"
local CMD = {}

local function start()
    
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(commands[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    skynet.register("." .. name)
end)