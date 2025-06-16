local skynet = require "skynet"
require "skynet.manager"

local CMD = {}

function CMD.getRobot(gameid, num)
    
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        end
    end)
end)