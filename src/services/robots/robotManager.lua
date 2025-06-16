local skynet = require "skynet"
require "skynet.manager"

local CMD = {}



skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            skynet.ignoreret()
            LOG.error("robotManager cmd not found %s", cmd)
        end
    end)
end)