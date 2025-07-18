local skynet = require "skynet"
local log = require "log"
require "skynet.manager"
local name = "robotManager"
local config = require "robot.config"
local robotDatas = {}
local freeRobots = {}
local usingRobots = {}
local CMD = {}

-- 获取空闲机器人id
local function getFreeRobotid()
    if #freeRobots > 0 then
        return table.remove(freeRobots, 1)
    end
    return nil
end

local function start()
    local dbSvr = skynet.localname(".db")
    local robots = skynet.call(dbSvr, "lua", "db","getRobots", config.idbegin, config.idend)
    if robots then
        for _,robot in pairs(robots) do
            robotDatas[robot.userid] = robot
            table.insert(freeRobots, robot.userid)
        end
    end
end

-- 获取机器人
function CMD.getRobots(gameid, num)
    if not gameid or not num or gameid == 0 or num <= 0 then
        return nil
    end

    local datas = {}
    local n = 0
    for i = 1, num do
        local id = getFreeRobotid()
        log.info("getRobots %s %d", id, n)
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

-- 返回机器人
function CMD.returnRobots(ids)
    for _,id in ipairs(ids) do
        if usingRobots[id] then
            usingRobots[id] = nil
            table.insert(freeRobots, id)
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
            log.error("robotManager cmd not found %s", cmd)
        end
    end)
    skynet.register("." .. name)

    start()
end)