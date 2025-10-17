local config = {
    MATCH_ROOM_WAITTING_CONNECT_TIME = 8, -- 等待连接时间
    MATCH_ROOM_GAME_TIME = 900, -- 游戏时间
    ROOM_STATUS = { -- 游戏状态
        NONE = 0,
        WAITTING_CONNECT = 1,
        START = 2,
        END = 3,
        HALFTIME = 4, -- 局间
    },
    PLAYER_STATUS = { -- 玩家状态
        LOADING = 1,
        OFFLINE = 2,
        ONLINE = 3,
        PLAYING = 4,
        READY = 5
    },

    LOG_TYPE = {
        CREATE_ROOM = 0,
        DESTROY_ROOM = 1,
        GAME_START = 2,
        GAME_END = 3,
        GAME_RESULT = 4,
        VOTE_DISBAND_START = 5,  -- 投票解散开始
        VOTE_DISBAND_END = 6,    -- 投票解散结束
    },

    LOG_RESULT_TYPE = {
        GAME_END = 1,
    },

    RESULT_TYPE = {
        NONE = 0,
        WIN = 1,
        LOSE = 2,
        DRAW = 3,
        ESCAPE = 4,
    },

    SPROTO = {
        C2S = "game10001_c2s",
        S2C = "game10001_s2c",
    },

    ROOM_END_FLAG = {
        NONE = 0,
        GAME_END = 1,
        OUT_TIME_WAITING = 2,
        OUT_TIME_PLAYING = 3,
        VOTE_DISBAND = 4,        -- 投票解散
        OWNER_DISBAND = 5,        -- 房主解散
    },

    PRIVATE_ROOM_MODE = {
        [0] = {
            name = "3局2胜",
            maxCnt = 3,
            winCnt = 2
        },
        [1] = {
            name = "5局3胜",
            maxCnt = 5,
            winCnt = 3
        },
        [2] = {
            name = "7局4胜",
            maxCnt = 7,
            winCnt = 4
        },
    },

    RATING_CONFIG = {
        K_base = 65,
        S_max = 6000,
        initial_score = 1000,
        min_score = 0,
        zero_sum_mode = false  -- 启用零和模式
    }
}

return config