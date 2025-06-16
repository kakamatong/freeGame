local config = require("games.10001.configLogic")
local logic = {}
logic.outHandInfo = {} -- 出招信息
logic.roundid = 0 -- 轮次id
logic.roundNum = 0 -- 轮次
logic.stepBeginTime = 0 -- 步骤开始时间
logic.outHandNum = 0 -- 出招次数
logic.stepid = 0 -- 步骤id
logic.tableHandler = nil -- 桌子处理

local logicHandler = {}

local function tableLength(t)
    local count = 0
    for _, _ in pairs(t) do
        count = count + 1
    end
    return count
end

function logic.init(playerNum, rule, tableHandler)
    logic.playerNum = playerNum
    logic.tableHandler = tableHandler
end

-- 设置玩家数量
function logic.setPlayerNum(playerNum)
    logic.playerNum = playerNum
end

-- 开始游戏
function logic.startGame()
    LOG.info("startGame")
    logic.startStep(config.GAME_STEP.START)
end

-- 出招
function logic.outHand(seatid, args)
    if logic.stepid ~= config.GAME_STEP.OUT_HAND then
        return
    end
    local flag = args.flag
    LOG.info("outHand %d %d", seatid, flag)
    if not logic.outHandInfo[seatid] then
        logic.outHandInfo[seatid] = flag
    else
        -- 已经出过招
        logic.outHandInfo[seatid] = flag
    end

    if tableLength(logic.outHandInfo) == logic.playerNum then
        -- 比较大小
        for seat, tmpflag in pairs(logic.outHandInfo) do
            logic.sendOutHandInfo(config.SEAT_FLAG.SEAT_ALL, seat, tmpflag)
            logic.sendPlayerAttitude(seat, config.PLAYER_ATTITUDE.OUT_HAND)
        end
        logic.compare()

        --test code
        logic.stopStepGameEnd()
    else
        logic.sendPlayerAttitude(seatid, config.PLAYER_ATTITUDE.READY)
        -- 下发自己的
        logic.sendOutHandInfo(seatid,seatid, flag)
    end
end

-- 比较大小
function logic.compare()
    LOG.info("compare")
    local maxFlag = 0
    local maxSeatid = 0
    local result = 0x0000
    for seatid, flag in pairs(logic.outHandInfo) do
        result = result & flag
    end

    logic.outHandNum = logic.outHandNum + 1

    if result == config.HAND_RESULT.ROCK_WIN then
        -- 布胜
        logic.sendResult(config.HAND_FLAG.ROCK)
    elseif result == config.HAND_RESULT.PAPER_WIN then
        -- 石头胜
        logic.sendResult(config.HAND_FLAG.PAPER)
    elseif result == config.HAND_RESULT.SCISSORS_WIN then
        -- 剪刀胜
        logic.sendResult(config.HAND_FLAG.SCISSORS)
    else
        logic.sendResult(0)
    end
end

function logic.sendResult(result)
    local playerResult = {}
    for seatid, flag in pairs(logic.outHandInfo) do
        local tmp = {}
        local endflag = 0
        if flag == result then
            endflag = 1
        elseif result == 0 then
            endflag = 2
        end
        tmp.seat = seatid
        tmp.outHand = flag
        tmp.endResult = endflag
        table.insert(playerResult, tmp)
    end
    local info = {
        roundNum = logic.roundNum,
        outHandNum = logic.outHandNum,
        continue = 0,
        info = playerResult,
    }

    logic.sendToAllClient("reportGameRoundResult", info)
end

function logic.sendPlayerAttitude(seatid, flag)
    if seatid == config.SEAT_FLAG.SEAT_ALL then
        logic.sendToAllClient("reportGamePlayerAttitude", {
            seat = seatid,
            att = flag,
        })
    else
        logic.sendToOneClient(seatid, "reportGamePlayerAttitude", {
            seat = seatid,
            att = flag,
        })
    end 
end

function logic.sendOutHandInfo(toseat, seatid, flag)
    if toseat == config.SEAT_FLAG.SEAT_ALL then
        logic.sendToAllClient("reportGameOutHand", {
            seat = seatid,
            flag = flag,
        })
    else
        logic.sendToOneClient(toseat, "reportGameOutHand", {
            seat = seatid,
            flag = flag,
        })
    end
    
end

-- 获取当前步骤id
function logic.getStepId()
    return logic.stepid
end

-- 设置当前步骤开始时间
function logic.setStepBeginTime()
    logic.stepBeginTime = os.time()
end

-- 获取当前步骤时间长度
function logic.getStepTimeLen(stepid)
    return config.STIP_TIME_LEN[stepid] or 0
end

-- 开始步骤开始游戏
function logic.startStepStartGame()
    logic.sendToAllClient("reportGameStep", {
        stepid = config.GAME_STEP.START,
    })

    logic.roundNum = logic.roundNum + 1
    -- 下发roundNum
end

-- 停止步骤开始游戏
function logic.stopStepStartGame()
    logic.startStep(config.GAME_STEP.OUT_HAND)
end

-- 步骤开始游戏超时
function logic.onStepStartGameTimeout()
    logic.stopStep(config.GAME_STEP.START)
end

-- 开始步骤出招
function logic.startStepOutHand()
    logic.sendToAllClient("reportGameStep", {
        stepid = config.GAME_STEP.OUT_HAND,
    })

    for i = 1, logic.playerNum do
        logic.sendPlayerAttitude(i, config.PLAYER_ATTITUDE.THINKING)
    end
end

-- 停止步骤出招
function logic.stopStepOutHand()

end

-- 步骤出招超时
function logic.onStepOutHandTimeout()

end

-- 开始一轮结束步骤
function logic.startStepRoundEnd()

end

-- 停止一轮结束步骤
function logic.stopStepRoundEnd()

end

-- 一轮结束步骤超时
function logic.onStepRoundEndTimeout()

end

-- 开始游戏结束步骤
function logic.startStepGameEnd()

end

-- 停止游戏结束步骤
function logic.stopStepGameEnd()
    logic.stepid = config.GAME_STEP.NONE
    logic.tableHandler.gameEnd()
end

-- 游戏结束步骤超时
function logic.onStepGameEndTimeout()

end

-- 开始步骤
function logic.startStep(stepid)
    LOG.info("startStep %d", stepid)
    logic.setStepBeginTime()
    logic.stepid = stepid
    if stepid == config.GAME_STEP.START then
        logic.startStepStartGame()
    elseif stepid == config.GAME_STEP.OUT_HAND then
        logic.startStepOutHand()
    elseif stepid == config.GAME_STEP.ROUND_END then
        logic.startStepRoundEnd()
    elseif stepid == config.GAME_STEP.GAME_END then
        logic.startStepGameEnd()
    end
end

-- 停止步骤
function logic.stopStep(stepid)
    LOG.info("stopStep %d", stepid)
    if stepid == config.GAME_STEP.START then
        logic.stopStepStartGame()
    elseif stepid == config.GAME_STEP.OUT_HAND then
        logic.stopStepOutHand()
    elseif stepid == config.GAME_STEP.ROUND_END then
        logic.stopStepRoundEnd()
    elseif stepid == config.GAME_STEP.GAME_END then
        logic.stopStepGameEnd()
    end
end

-- 步骤超时
function logic.onStepTimeout(stepid)
    LOG.info("onStepTimeout %d", stepid)
    if stepid == config.GAME_STEP.START then
        logic.onStepStartGameTimeout()
    elseif stepid == config.GAME_STEP.OUT_HAND then
        logic.onStepOutHandTimeout()
    elseif stepid == config.GAME_STEP.ROUND_END then
        logic.onStepRoundEndTimeout()
    elseif stepid == config.GAME_STEP.GAME_END then
        logic.onStepGameEndTimeout()
    end
end

function logic.onRelinkStartGame(seat)

end

function logic.onRelinkOutHand(seat)
    if logic.outHandInfo[seat] then
        logic.sendOutHandInfo(seat, seat, logic.outHandInfo[seat])
        logic.sendPlayerAttitude(seat, config.PLAYER_ATTITUDE.READY)
    else
        logic.sendPlayerAttitude(seat, config.PLAYER_ATTITUDE.THINKING)
    end
end

function logic.onRelinkRoundEnd(seat)

end

function logic.onRelinkGameEnd(seat)

end

-- 重新连接
function logic.onRelink(seat)
    LOG.info("onRelink %d", seat)
    local stepid = logic.getStepId()
    logic.sendToOneClient(seat, "reportGameStep", {
        stepid = stepid,
    })

    if stepid == config.GAME_STEP.START then
        logic.onRelinkStartGame(seat)
    elseif stepid == config.GAME_STEP.OUT_HAND then
        logic.onRelinkOutHand(seat)
    elseif stepid == config.GAME_STEP.ROUND_END then
        logic.onRelinkRoundEnd(seat)
    elseif stepid == config.GAME_STEP.GAME_END then
        logic.onRelinkGameEnd(seat)
    end
end

-- 定时器每0.1s调用一次
function logic.update()
    --LOG.info("update")
    local stepid = logic.getStepId()
    if stepid == config.GAME_STEP.NONE then
        return
    end
    local currentTime = os.time()
    --LOG.info("currentTime %d, logic.stepBeginTime %d", currentTime, logic.stepBeginTime)
    local timeLen = currentTime - logic.stepBeginTime
    if timeLen > logic.getStepTimeLen(stepid) then
        logic.onStepTimeout(stepid)
    end
end

-- 发送消息给所有玩家
function logic.sendToAllClient(name, data)
    if logic.tableHandler then
        logic.tableHandler.sendToAllClient(name, data)
    end
end

-- 发送消息给单个玩家
function logic.sendToOneClient(seat, name, data)
    if logic.tableHandler then
        logic.tableHandler.sendToOneClient(seat, name, data)
    end
end

------------------------------------------------------------------------------------------------------------
-- 游戏逻辑接口提供给table调用
-- 重新连接
function logicHandler.relink(seat)
    logic.onRelink(seat)
end

-- 开始游戏
function logicHandler.startGame()
    logic.startGame()
end

-- 出招
function logicHandler.outHand(seatid, args)
    logic.outHand(seatid, args)
end

-- 初始化
function logicHandler.init(playerNum, rule, tableHandler)
    logic.init(playerNum, rule, tableHandler)
end

-- 定时器每0.1s调用一次
function logicHandler.update()
    logic.update()
end

return logicHandler