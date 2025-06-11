local config = {
    WAITTING_CONNECT_TIME = 8, -- 等待连接时间
    GAME_TIME = 10, -- 游戏时间
    GAME_STATUS = { -- 游戏状态
        NONE = 0,
        WAITTING_CONNECT = 1,
        START = 2,
        END = 3
    },
    PLAYER_STATUS = { -- 玩家状态
        LOADING = 1,
        DISCONNECT = 2,
        PLAYING = 3,
    },
}

return config