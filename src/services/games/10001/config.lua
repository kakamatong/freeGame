local config = {
    WAITTING_CONNECT_TIME = 8, -- 等待连接时间
    GAME_TIME = 900, -- 游戏时间
    GAME_STATUS = { -- 游戏状态
        NONE = 0,
        WAITTING_CONNECT = 1,
        START = 2,
        END = 3
    },
    PLAYER_STATUS = { -- 玩家状态
        LOADING = 1,
        OFFLINE = 2,
        PLAYING = 3,
    },

    LOG_TYPE = {
        CREATE_ROOM = 0,
        DESTROY_ROOM = 1,
        GAME_START = 2,
        GAME_END = 3,
        GAME_RESULT = 4,
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
}

return config