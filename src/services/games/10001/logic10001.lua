local logic = {}
local outHandInfo = {}
local stepid = 0
local GAME_STEP = {
    OUT_HAND = 1,
    COMPARE = 2,
    END = 3,
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

local 

local function tableLength(t)
    local count = 0
    for _, _ in pairs(t) do
        count = count + 1
    end
    return count
end

function logic.init(playerNum, rule)
    logic.playerNum = playerNum
end

function logic.setPlayerNum(playerNum)
    logic.playerNum = playerNum
end

function logic.startGame()
    LOG.info("startGame")
end

function logic.outHand(seatid, flag)
    LOG.info("outHand %d %d", seatid, flag)
    if not outHandInfo[seatid] then
        outHandInfo[seatid] = flag
    else
        -- 已经出过招
    end

    if tableLength(outHandInfo) == logic.playerNum then
        -- 比较大小
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

    if result == HAND_RESULT.DRAW then
        -- 平局
    elseif result == HAND_RESULT.ROCK_WIN then
        -- 布胜
    elseif result == HAND_RESULT.PAPER_WIN then
        -- 石头胜
    elseif result == HAND_RESULT.SCISSORS_WIN then
        -- 剪刀胜
    end
end

return logic