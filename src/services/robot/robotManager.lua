local skynet = require "skynet"
require "skynet.manager"
local name = "robotManager"
local config = require "robot.config"
local robotDatas = {}
local freeRobots = {}
local usingRobots = {}
local CMD = {}

local function getFreeRobotid()
    if #freeRobots > 0 then
        return table.remove(freeRobots, 1)
    end
    return nil
end

function CMD.getRobots(gameid, num)
    if not gameid or not num or gameid == 0 or num <= 0 then
        return nil
    end

    local datas = {}
    local n = 0
    for i = 1, num do
        local id = getFreeRobotid()
        if id and robotDatas[id] then
            table.insert(datas, robotDatas[id])
            usingRobots[id] = true
            n = n + 1
            if n >= num then
                break
            end
        end
    end

    return datas
end

function CMD.returnRobots(ids)
    for _,id in ipairs(ids) do
        if usingRobots[id] then
            usingRobots[id] = nil
            table.insert(freeRobots, id)
        end
    end
end

function CMD.robotEnter(gameid, roomid, userid)
    local robot = robotDatas[userid]
    if not robot then
        LOG.error("robotEnter robot not found %d", userid)
        return
    end
    
    local gameManager = skynet.localname(".gameManager")
    if not gameManager then
        LOG.error("robotEnter gameManager not found")
        return
    end
    skynet.send(gameManager, "lua", "playerEnter", gameid, roomid, robot)
    skynet.send(gameServer, "lua", "connectGame", gameid, roomid, userid)
end

function CMD.start()
    local dbSvr = skynet.localname(".dbserver")
    local robots = skynet.call(dbSvr, "lua", "func","getRobots", config.idbegin, config.idend)
    if robots then
        for _,robot in pairs(robots) do
            robotDatas[robot.userid] = robot
            table.insert(freeRobots, robot)
        end
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