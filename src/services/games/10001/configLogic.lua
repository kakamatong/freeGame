local GAME_STEP = {
    NONE = 0,
    START = 1,
    OUT_HAND = 2,
    ROUND_END = 3,
    GAME_END = 4,
}

local HAND_FLAG = {
    ROCK = 0x0001, -- 石头
    PAPER = 0x0010, -- 布
    SCISSORS = 0x0100, -- 剪刀
}

local HAND_RESULT = {
    DRAW = 0x0000, -- 平局
    ROCK_WIN = 0x0101, -- 石头胜
    PAPER_WIN = 0x0011, -- 布胜
    SCISSORS_WIN = 0x0110, -- 剪刀胜
    DRAW2 = 0x0111,
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
    [GAME_STEP.OUT_HAND] = 10,
    [GAME_STEP.ROUND_END] = 1,
    [GAME_STEP.GAME_END] = 0,
}

local SEAT_FLAG = {
    SEAT_ALL = 0,
    SEAT_1 = 1,
    SEAT_2 = 2,
    SEAT_3 = 3,
}

local configLogic = {
    GAME_STEP = GAME_STEP,
    HAND_FLAG = HAND_FLAG,
    HAND_RESULT = HAND_RESULT,
    RESULT_TYPE = RESULT_TYPE,
    PLAYER_ATTITUDE = PLAYER_ATTITUDE,
    STIP_TIME_LEN = STIP_TIME_LEN,
    SEAT_FLAG = SEAT_FLAG,
}

return configLogic