require "skynet"
local config = require "games.10001.configLogic"
local aiHandler = {}
local aiLogic = {}
local XY = {}
aiLogic.stepid = 0
aiLogic.roomHandlerAi = nil
aiLogic.stepBeginTime = 0
aiLogic.STEP_TIME = {
    [config.GAME_STEP.OUT_HAND] = 3,
}

aiLogic.timeFlag = {
    [config.GAME_STEP.OUT_HAND] = false,
}
aiLogic.seat = 0
aiLogic.data = nil


function aiLogic.dealStep()
    if aiLogic.stepid == config.GAME_STEP.OUT_HAND then
        aiLogic.dealGameOutHand()
    end
end

function aiLogic.dealGameOutHand()
    LOG.info("XY.dealGameOutHand", seat, data)
    aiLogic.timeFlag[config.GAME_STEP.OUT_HAND] = false
    if aiLogic.data.att == config.PLAYER_ATTITUDE.THINKING then
        local flags = {
            config.HAND_FLAG.ROCK,
            config.HAND_FLAG.PAPER,
            config.HAND_FLAG.SCISSORS
        }
        local backData = {
            flag = flags[math.random(1, #flags)]
        }
        aiLogic.roomHandlerAi.onAiMsg(aiLogic.seat, "gameOutHand", backData)
    end
end

function aiLogic.startStep(stepid)
    aiLogic.stepid = stepid
    aiLogic.stepBeginTime = os.time()
end

function aiLogic.update()
    local stepid = aiLogic.stepid
    local timeNow = os.time()
    local timeLen = aiLogic.STEP_TIME[stepid]
    if aiLogic.timeFlag[stepid] and timeLen and (timeNow - aiLogic.stepBeginTime) >= timeLen then
        aiLogic.dealGameOutHand()
    end
end

------------------------------------------------------------------------------------------------------------ 处理协议
-- 处理协议
function XY.reportGameStep(seat, data)
    aiLogic.startStep(data.stepid)
end

function XY.reportGamePlayerAttitude(seat, data)
    LOG.info("XY.reportGamePlayerAttitude", seat, data)
    aiLogic.seat = seat
    aiLogic.data = data
    aiLogic.timeFlag[aiLogic.stepid] = true
end

------------------------------------------------------------------------------------------------------------ ai消息处理
function aiHandler.onMsg(seat, name, data)
    LOG.info("aiHandler.onMsg", seat, name, data)
    if XY[name] then
        XY[name](seat, data)
    else
        LOG.info("aiHandler.onMsg", seat, name, data, "not found")
    end
end

function aiHandler.init(roomHandlerAi)
    aiLogic.roomHandlerAi = roomHandlerAi
end

function aiHandler.update()
    aiLogic.update()
end

return aiHandler