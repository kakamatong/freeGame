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

-- 私人房间模式
config.PRIVATE_ROOM_MODE = {
    [0] = {
        name = "单局竞速",
        maxCnt = 1,
        winCnt = 1,
        desc = "谁先完成谁赢"
    },
    [1] = {
        name = "3局2胜",
        maxCnt = 3,
        winCnt = 2,
        desc = "三局两胜制"
    },
    [2] = {
        name = "5局3胜",
        maxCnt = 5,
        winCnt = 3,
        desc = "五局三胜制"
    },
}

-- 评分配置（ELO系统）
config.RATING_CONFIG = {
    K_base = 65,
    S_max = 6000,
    initial_score = 1000,
    min_score = 0,
    zero_sum_mode = false
}

-- 地图配置
config.MAP = {
    DEFAULT_ROWS = 10,
    DEFAULT_COLS = 10,
    ICON_TYPES = 10,
    
    MIN_PLAYERS = 2,
    MAX_PLAYERS = 4,
}

-- 消息转发类型
config.FORWARD_MESSAGE_TYPE = {
    TALK = 1,
}

return config
