local skynet = require "skynet"
local log = require "log"
local CMD = {}
local config = require "robot.config"
local robotDatas = {}
local freeRobots = {}
local usingRobots = {}
require "skynet.manager"
local bload = false
local dbSvr = nil
local function start()
    dbSvr = skynet.localname(CONFIG.SVR_NAME.DB)
end

-- 获取空闲机器人id
local function getFreeRobotid()
    if #freeRobots > 0 then
        return table.remove(freeRobots, 1)
    end
    return nil
end

local function load()
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

    if not bload then
        load()
        bload = true
    end

    local datas = {}
    local n = 0
    for i = 1, num do
        local id = getFreeRobotid()
        log.info("getRobots %s %d", id, n)
        if id and robotDatas[id] then
            -- 机器人战力
            local rices = skynet.call(dbSvr, "lua", "db", "getUserRichesByType", id, CONFIG.RICH_TYPE.COMBAT_POWER)
            local cp = 0
            if rices then
                cp = rices.richNums
            end
            robotDatas[id] = robotDatas[id] or {}
            robotDatas[id].cp = cp

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
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)
    skynet.register(CONFIG.SVR_NAME.ROBOT)
    start()
end)