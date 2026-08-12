--[[
    configLogic.lua
    算24点(10003)游戏逻辑配置
    对应客户端游戏逻辑配置
]]

local config = {}

-- 游戏阶段
config.GAME_STEP = {
    NONE = 0,
    START = 1,     -- 开始阶段（1秒，发牌）
    PLAYING = 2,   -- 答题阶段（玩家提交算式，第一个答对者直接结束本局）
    END = 3,       -- 结算阶段
}

-- 阶段时间（秒），PLAYING在init时会被本局maxTime覆盖
config.STEP_TIME_LEN = {
    [config.GAME_STEP.START] = 1,
    [config.GAME_STEP.PLAYING] = 30,
    [config.GAME_STEP.END] = 0,
}

-- 游戏状态
config.GAME_STATUS = {
    NONE = 0,
    WAITING = 1,        -- 等待玩家准备
    READY = 2,          -- 准备就绪
    PLAYING = 3,        -- 游戏中
    PAUSED = 4,         -- 暂停
    END = 5,            -- 游戏结束
}

-- 玩家状态
config.PLAYER_STATUS = {
    LOADING = 1,        -- 加载中
    OFFLINE = 2,        -- 离线
    ONLINE = 3,         -- 在线
    PLAYING = 4,        -- 游戏中
    READY = 5,          -- 已准备
    FINISHED = 6,       -- 已完成
}

-- 游戏结束类型
config.END_TYPE = {
    NONE = 0,
    WIN = 1,            -- 有人答对（本局正常结束）
    TIMEOUT = 2,        -- 超时无人答对
    DISBAND = 4,        -- 房间解散
}

-- 目标值
config.TARGET_VALUE = 24

-- 每局发牌数量
config.DEAL_COUNT = 4

return config
