local config = {
    SPROTO = {
        C2S = "game10002_c2s",
        S2C = "game10002_s2c",
    },
}

-- 匹配房间配置
config.MATCH_ROOM_WAITTING_CONNECT_TIME = 8  -- 等待连接时间(秒)
config.MATCH_ROOM_GAME_TIME = 300            -- 游戏时间(秒)

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

-- 评分配置（ELO系统）
config.RATING_CONFIG = {
    K_base = 65,
    S_max = 10000,
    initial_score = 1000,
    min_score = 0,
    zero_sum_mode = false
}

-- 地图配置，地图默认是10*10的，配置最大为8*8（外面需要留一圈空白消除）
config.MAP = {
    DEFAULT_ROWS = 5, --10
    DEFAULT_COLS = 6, --10
    ICON_TYPES = 11, --10
    
    MIN_PLAYERS = 2,
    MAX_PLAYERS = 6,
}

-- 私人房配置
config.PRIVATE_ROOM = {
    MAX_PLAYERS = 6,  -- 私人房最大玩家数
}

-- AI配置
config.AI = {
    TICK_INTERVAL = 5,           -- AI执行间隔（秒）
    ACTION_PROBABILITY = 60,      -- AI行动概率（百分比）
}

-- 计分配置
config.SCORING = {
    -- 普通匹配ELO配置（炉石模式）
    MATCH = {
        K_base = 32,                -- 基础K值
        S_max = 3000,              -- 高分阈值（超过此分后加分减少）
        initial_score = 1000,       -- 初始分数
        min_score = 0,             -- 最低分数
        low_score_threshold = 1000, -- 低分阈值（低于此分未完成得0分）
    },
    -- 私人房计分配置
    PRIVATE = {
        -- 第一名得分 = 玩家数，其余名次递减，未完成得0分
    }
}

-- 消息转发类型
config.FORWARD_MESSAGE_TYPE = {
    TALK = 1,
}

return config
