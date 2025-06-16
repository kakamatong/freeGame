local skynet = require "skynet"
require "skynet.manager"
local name = "robotManager"
local config = require "robot.config"
local robotDatas = {}
local CMD = {}
function CMD.getRobots(gameid, num)
    
end

function CMD.start()
    local dbSvr = skynet.localname(".dbserver")
    local robots = skynet.call(dbSvr, "lua", "func","getRobots", config.idbegin, config.idend)
    if robots then
        robotDatas = robots
    end
end

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
    skynet.register("." .. name)
end)