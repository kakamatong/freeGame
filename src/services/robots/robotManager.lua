local skynet = require "skynet"
require "skynet.manager"
local name = "robotManager"
local robotConfig = {10001}
local robotList = {}
local CMD = {}

function CMD.getRobots(gameid, num)
    local robotSvr = robotList[gameid]
    if not robotSvr then
        return nil
    end
    local robots = skynet.call(robotSvr, "lua", "getRobots", gameid, num)
    return robots
end

function CMD.start()
    for _, gameid in ipairs(robotConfig) do
        local robot = skynet.newservice(gameid .. "/robot")
        robotList[gameid] = robot
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