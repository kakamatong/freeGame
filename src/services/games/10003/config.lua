--[[
    config.lua
    算24点(10003)房间配置
    功能：
    1. 房间状态、玩家状态、日志类型定义
    2. 发牌数字范围、每局答题时间
    3. 私人房局数配置、计分与AI配置
]]

local config = {
    SPROTO = {
        C2S = "game10003_c2s",
        S2C = "game10003_s2c",
    },
}

-- 匹配房间配置
config.MATCH_ROOM_WAITTING_CONNECT_TIME = 8   -- 等待连接时间(秒)
config.MATCH_ROOM_GAME_TIME = 300             -- 房间总游戏时间(秒)

-- 房间状态
config.ROOM_STATUS = {
    NONE = 0,
    WAITTING_CONNECT = 1,
    START = 2,
    END = 3,
    HALFTIME = 4,
}

-- 玩家状态
config.PLAYER_STATUS = {
    LOADING = 1,
    OFFLINE = 2,
    ONLINE = 3,
    PLAYING = 4,
    READY = 5,
    FINISHED = 6,
}

-- 日志类型
config.LOG_TYPE = {
    CREATE_ROOM = 0,
    DESTROY_ROOM = 1,
    GAME_START = 2,
    GAME_END = 3,
    GAME_RESULT = 4,
    VOTE_DISBAND_START = 5,
    VOTE_DISBAND_END = 6,
}

-- 日志结果类型
config.LOG_RESULT_TYPE = {
    GAME_END = 1,
}

-- 结果类型
config.RESULT_TYPE = {
    NONE = 0,
    WIN = 1,
    LOSE = 2,
    DRAW = 3,
    ESCAPE = 4,
}

-- 房间结束标记
config.ROOM_END_FLAG = {
    NONE = 0,
    GAME_END = 1,
    OUT_TIME_WAITING = 2,
    OUT_TIME_PLAYING = 3,
    VOTE_DISBAND = 4,
    OWNER_DISBAND = 5,
}

-- 私人房配置
config.PRIVATE_ROOM = {
    MAX_PLAYERS = 6,  -- 私人房最大玩家数
}

-- 发牌数字范围（可配置）
config.NUMBER_RANGE = {
    MIN = 1,  -- 最小数字
    MAX = 9,  -- 最大数字
}

-- 每局答题时间(秒)，超时无人答对则本局无胜者
config.ROUND_TIME = 30

-- 私人房局数配置（创建时通过 privateRule.playNum 传入，不在白名单则取默认3）
config.PRIVATE_ROOM_MODE = {
    [3] = { name = "3局", maxCnt = 3 },
    [5] = { name = "5局", maxCnt = 5 },
    [7] = { name = "7局", maxCnt = 7 },
}

-- 计分配置（参考10002）
config.SCORING = {
    -- 匹配模式计分
    MATCH = {
        initial_score = 1000,       -- 初始分数
        min_score = 0,              -- 最低分数
        -- 未答对扣分档位（threshold: 当前分数低于此值时适用）
        unfinished_penalty = {
            { threshold = 200,  penalty = 0 },   -- 0-199分: 0分
            { threshold = 500,  penalty = 1 },   -- 200-499分: -1分
            { threshold = 1000, penalty = 2 },   -- 500-999分: -2分
            { threshold = nil,  penalty = 3 },   -- 1000分以上: -3分
        },
    },
    -- 私人房计分（答对者按排名计分，未答对0分）
    PRIVATE = {},
}

-- AI配置
config.AI = {
    ACTION_PROBABILITY = 60,                 -- AI提交概率（百分比）
    SUBMIT_DELAY = { MIN = 2, MAX = 8 },     -- 提交延迟区间（秒），避免AI秒答碾压真人
}

-- 消息转发类型
config.FORWARD_MESSAGE_TYPE = {
    TALK = 1,
}

return config
