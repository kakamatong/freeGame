local logic = {}
local outHandInfo = {}
local roundid = 0
local roundNum = 0
local stepBeginTime = 0
local outHandNum = 0
logic.stepid = 0
logic.table = nil
local GAME_STEP = {
    NONE = 0,
    START = 1,
    OUT_HAND = 2,
    ROUND_END = 3,
    GAME_END = 4,
}

local HAND_FLAG = {
    ROCK = 0x0001, -- 石头
    PAPER = 0x0010, -- 剪刀
    SCISSORS = 0x0100, -- 布
}

local HAND_RESULT = {
    DRAW = 0x0000, -- 平局
    ROCK_WIN = 0x0101, -- 石头胜
    PAPER_WIN = 0x0011, -- 剪刀胜
    SCISSORS_WIN = 0x0110, -- 布胜
}

local RESULT_TYPE = {
    DRAW = 0,
    WIN = 1,
    LOSE = 2,
}

local PLAYER_ATTITUDE = {
    THINKING = 0, -- 思考
    READY = 1, -- 准备
    OUT_HAND = 2, -- 出招
}

local STIP_TIME_LEN = {
    [GAME_STEP.START] = 1,
    [GAME_STEP.OUT_HAND] = 30,
    [GAME_STEP.ROUND_END] = 1,
    [GAME_STEP.GAME_END] = 0,
}

local SEAT_FLAG = {
    SEAT_ALL = 0,
    SEAT_1 = 1,
    SEAT_2 = 2,
    SEAT_3 = 3,
}

local function tableLength(t)
    local count = 0
    for _, _ in pairs(t) do
        count = count + 1
    end
    return count
end

function logic.init(playerNum, rule, table)
    logic.playerNum = playerNum
    logic.table = table
end

function logic.setPlayerNum(playerNum)
    logic.playerNum = playerNum
end

function logic.startGame()
    LOG.info("startGame")
    logic.startStep(GAME_STEP.START)
end

function logic.outHand(seatid, args)
    if logic.stepid ~= GAME_STEP.OUT_HAND then
        return
    end
    local flag = args.flag
    LOG.info("outHand %d %d", seatid, flag)
    if not outHandInfo[seatid] then
        outHandInfo[seatid] = flag
    else
        -- 已经出过招
        outHandInfo[seatid] = flag
    end

    if tableLength(outHandInfo) == logic.playerNum then
        -- 比较大小
        for seat, tmpflag in pairs(outHandInfo) do
            logic.sendOutHandInfo(SEAT_FLAG.SEAT_ALL, seat, tmpflag)
        end
        logic.compare()
        --test code
        logic.stopStepGameEnd()
    else
        -- 下发自己的
        logic.sendOutHandInfo(seatid,seatid, flag)
    end
end

function logic.compare()
    LOG.info("compare")
    local maxFlag = 0
    local maxSeatid = 0
    local result = 0x0000
    for seatid, flag in pairs(outHandInfo) do
        result = result & flag
    end

    outHandNum = outHandNum + 1

    if result == HAND_RESULT.ROCK_WIN then
        -- 布胜
        logic.sendResult(HAND_FLAG.ROCK)
    elseif result == HAND_RESULT.PAPER_WIN then
        -- 石头胜
        logic.sendResult(HAND_FLAG.PAPER)
    elseif result == HAND_RESULT.SCISSORS_WIN then
        -- 剪刀胜
        logic.sendResult(HAND_FLAG.SCISSORS)
    else
        logic.sendResult(0)
    end
end

function logic.sendResult(result)
    local playerResult = {}
    for seatid, flag in pairs(outHandInfo) do
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
        roundNum = roundNum,
        outHandNum = outHandNum,
        continue = 0,
        info = playerResult,
    }

    logic.sendToAllClient("reportGameRoundResult", info)
end

function logic.sendPlayerAttitude(seatid, flag)
    logic.sendToOneClient(seatid, "reportGamePlayerAttitude", {
        seat = seatid,
        att = flag,
    })
end

function logic.sendOutHandInfo(toseat, seatid, flag)
    if toseat == SEAT_FLAG.SEAT_ALL then
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
    stepBeginTime = os.time()
end

-- 获取当前步骤时间长度
function logic.getStepTimeLen(stepid)
    return STIP_TIME_LEN[stepid] or 0
end

-- 开始步骤开始游戏
function logic.startStepStartGame()
    logic.sendToAllClient("reportGameStep", {
        stepid = GAME_STEP.START,
    })

    roundNum = roundNum + 1
    -- 下发roundNum
end

-- 停止步骤开始游戏
function logic.stopStepStartGame()
    logic.startStep(GAME_STEP.OUT_HAND)
end

-- 步骤开始游戏超时
function logic.onStepStartGameTimeout()
    logic.stopStep(GAME_STEP.START)
end

-- 开始步骤出招
function logic.startStepOutHand()
    logic.sendToAllClient("reportGameStep", {
        stepid = GAME_STEP.OUT_HAND,
    })

    for i = 1, logic.playerNum do
        logic.sendPlayerAttitude(i, PLAYER_ATTITUDE.THINKING)
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
    logic.stepid = GAME_STEP.NONE
    logic.table.gameEnd()
end

-- 游戏结束步骤超时
function logic.onStepGameEndTimeout()

end

-- 开始步骤
function logic.startStep(stepid)
    LOG.info("startStep %d", stepid)
    logic.setStepBeginTime()
    logic.stepid = stepid
    if stepid == GAME_STEP.START then
        logic.startStepStartGame()
    elseif stepid == GAME_STEP.OUT_HAND then
        logic.startStepOutHand()
    elseif stepid == GAME_STEP.ROUND_END then
        logic.startStepRoundEnd()
    elseif stepid == GAME_STEP.GAME_END then
        logic.startStepGameEnd()
    end
end

-- 停止步骤
function logic.stopStep(stepid)
    LOG.info("stopStep %d", stepid)
    if stepid == GAME_STEP.START then
        logic.stopStepStartGame()
    elseif stepid == GAME_STEP.OUT_HAND then
        logic.stopStepOutHand()
    elseif stepid == GAME_STEP.ROUND_END then
        logic.stopStepRoundEnd()
    elseif stepid == GAME_STEP.GAME_END then
        logic.stopStepGameEnd()
    end
end

-- 步骤超时
function logic.onStepTimeout(stepid)
    LOG.info("onStepTimeout %d", stepid)
    if stepid == GAME_STEP.START then
        logic.onStepStartGameTimeout()
    elseif stepid == GAME_STEP.OUT_HAND then
        logic.onStepOutHandTimeout()
    elseif stepid == GAME_STEP.ROUND_END then
        logic.onStepRoundEndTimeout()
    elseif stepid == GAME_STEP.GAME_END then
        logic.onStepGameEndTimeout()
    end
end

-- 定时器每0.1s调用一次
function logic.update()
    --LOG.info("update")
    local stepid = logic.getStepId()
    if stepid == GAME_STEP.NONE then
        return
    end
    local currentTime = os.time()
    --LOG.info("currentTime %d, stepBeginTime %d", currentTime, stepBeginTime)
    local timeLen = currentTime - stepBeginTime
    if timeLen > logic.getStepTimeLen(stepid) then
        logic.onStepTimeout(stepid)
    end
end

-- 发送消息给所有玩家
function logic.sendToAllClient(name, data)
    if logic.table then
        logic.table.sendToAllClient(name, data)
    end
end

-- 发送消息给单个玩家
function logic.sendToOneClient(seat, name, data)
    if logic.table then
        logic.table.sendToOneClient(seat, name, data)
    end
end

return logic