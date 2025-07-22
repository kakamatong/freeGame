require "skynet"
local log = require "log"
local config = require "games.10001.configLogic"
local aiHandler = {}
local aiLogic = {}
local XY = {}
aiLogic.data = {}

aiLogic.roomHandlerAi = nil

aiLogic.STEP_TIME = {
    [config.GAME_STEP.OUT_HAND] = 3,
}

-- function aiLogic.clear()
--     aiLogic.stepid = 0
--     aiLogic.stepBeginTime = 0
--     aiLogic.timeFlag = {
--         [config.GAME_STEP.OUT_HAND] = false,
--     }
--     aiLogic.seat = 0
--     aiLogic.data = nil
-- end

-- 处理出牌
function aiLogic.dealGameOutHand(seat)
    log.info("XY.dealGameOutHand")
    local data = aiLogic.data[seat]
    data.timeFlag = data.timeFlag or {}
    data.timeFlag[config.GAME_STEP.OUT_HAND] = false
    if data.attitude.att == config.PLAYER_ATTITUDE.THINKING then
        local flags = {
            config.HAND_FLAG.ROCK,
            config.HAND_FLAG.PAPER,
            config.HAND_FLAG.SCISSORS
        }
        local backData = {
            flag = flags[math.random(1, #flags)]
        }
        aiLogic.roomHandlerAi.onAiMsg(seat, "gameOutHand", backData)
    end
end

-- 开始步骤
function aiLogic.startStep(seat, stepid)
    aiLogic.data[seat] = aiLogic.data[seat] or {}
    aiLogic.data[seat].stepid = stepid
    aiLogic.data[seat].stepBeginTime = os.time()
end

-- 计时器更新
function aiLogic.update()
    for key, value in pairs(aiLogic.data) do
        local data = aiLogic.data[key]

        local stepid = data.stepid
        local timeNow = os.time()
        local timeLen = aiLogic.STEP_TIME[stepid]
        if data.timeFlag and data.timeFlag[stepid] and timeLen and (timeNow - data.stepBeginTime) >= timeLen then
            aiLogic.dealGameOutHand(key)
        end
    end
    
end

------------------------------------------------------------------------------------------------------------ 处理协议
-- 收到阶段消息
function XY.gameStep(seat, data)
    aiLogic.startStep(seat, data.stepid)
end

-- 收到玩家态度消息
function XY.gamePlayerAttitude(seat, data)
    log.info("XY.reportGamePlayerAttitude", seat, data)
    if seat == data.seat then
        local uData = aiLogic.data[seat]
        uData.seat = seat
        uData.attitude = data
        uData.timeFlag = uData.timeFlag or {}
        uData.timeFlag[uData.stepid] = true
    end
end

------------------------------------------------------------------------------------------------------------ ai消息处理
function aiHandler.onMsg(seat, name, data)
    if XY[name] then
        XY[name](seat, data)
    else
        log.info("aiHandler.onMsg not found")
    end
end

function aiHandler.init(roomHandlerAi, robotCnt)
    aiLogic.roomHandlerAi = roomHandlerAi
end

function aiHandler.update()
    aiLogic.update()
end

return aiHandler