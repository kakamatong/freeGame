--[[
    configLogic.lua
    连连看游戏逻辑配置
    对应客户端游戏逻辑配置
]]

local config = {}

-- 地图配置
config.MAP_CONFIG = {
    -- 默认地图大小（可以根据难度调整）
    DEFAULT_ROWS = 8,
    DEFAULT_COLS = 12,
    
    -- 简单模式
    EASY = {
        rows = 6,
        cols = 10,
        iconTypes = 6,  -- 图标种类数
    },
    
    -- 普通模式
    NORMAL = {
        rows = 8,
        cols = 12,
        iconTypes = 8,
    },
    
    -- 困难模式
    HARD = {
        rows = 10,
        cols = 14,
        iconTypes = 10,
    },
}

-- 游戏阶段（参考10001，简化为3个阶段）
config.GAME_STEP = {
    NONE = 0,           -- 无阶段
    START = 1,          -- 游戏开始阶段（1秒，下发地图）
    PLAYING = 2,        -- 游戏进行中阶段（玩家消除）
    END = 3,            -- 游戏结束阶段（结算）
}

-- 阶段时间配置（秒）
config.STEP_TIME_LEN = {
    [config.GAME_STEP.START] = 1,       -- 开始阶段1秒（给客户端加载地图的时间）
    [config.GAME_STEP.PLAYING] = 9999,  -- 游戏阶段，默认9999秒（实际需要根据配置调整）
    [config.GAME_STEP.END] = 0,         -- 结束阶段0秒（立即执行）
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
    NORMAL = 1,         -- 正常结束（有人完成）
    TIMEOUT = 2,        -- 超时结束
    ALL_FINISHED = 3,   -- 所有人都完成
    DISBAND = 4,        -- 房间解散
}

-- 胜利条件类型
config.WIN_CONDITION = {
    FIRST_FINISH = 1,   -- 谁先完成谁赢
    TIME_RANK = 2,      -- 按完成时间排名
    SCORE_RANK = 3,     -- 按分数排名
}

-- 地图生成配置
config.MAP_GENERATION = {
    -- 确保地图有解的最大尝试次数
    MAX_GENERATE_ATTEMPTS = 100,
    
    -- 图标类型范围（1-99，100以上为装饰）
    MIN_ICON_TYPE = 1,
    MAX_ICON_TYPE = 20,
}

-- 计分规则
config.SCORING = {
    -- 基础分
    BASE_SCORE = 100,
    
    -- 连击加成
    COMBO_BONUS = 10,
    
    -- 时间奖励（剩余秒数 * 系数）
    TIME_BONUS_FACTOR = 10,
    
    -- 完成奖励
    FINISH_BONUS = 500,
}

return config
