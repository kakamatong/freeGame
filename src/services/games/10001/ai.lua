require "skynet"
local config = require "games.10001.configLogic"
local aiHandler = {}
local aiLogic = {}
aiLogic.stepid = 0
aiLogic.roomHandlerAi = nil
function aiLogic.reportGamePlayerAttitude(seat, data)
    LOG.info("XY.reportGamePlayerAttitude", seat, data)
    if data.att == config.PLAYER_ATTITUDE.THINKING then
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

function aiLogic.reportGameStep(seat, data)
    LOG.info("XY.reportGameStep", seat, data)
    aiLogic.stepid = data.stepid
end

function aiHandler.onMsg(seat, name, data)
    LOG.info("aiHandler.onMsg", seat, name, data)
    if aiLogic[name] then
        aiLogic[name](seat, data)
    else
        LOG.info("aiHandler.onMsg", seat, name, data, "not found")
    end
end

function aiHandler.init(roomHandlerAi)
    aiLogic.roomHandlerAi = roomHandlerAi
end

return aiHandler