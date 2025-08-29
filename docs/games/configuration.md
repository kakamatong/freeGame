# Games服务配置说明

## 概述

Games服务的配置采用分层结构，从全局配置到游戏特定配置，提供灵活的参数调整能力。

## 配置层次结构

```mermaid
graph TB
    A[全局配置 CONFIG] --> B[Games配置 config.lua]
    B --> C[游戏配置 {gameid}/config.lua]
    C --> D[逻辑配置 configLogic.lua]
    
    E[环境配置] --> A
    F[启动脚本] --> A
```

## 全局配置 (CONFIG)

### 基础配置

全局配置定义在主配置文件中，包含服务基础参数：

```lua
CONFIG = {
    -- 服务名称配置
    SVR_NAME = {
        GAME_GATE = "wsGameGate",
        DB = "db",
        USER = "user",
        ROBOT = "robot"
    },
    
    -- 集群服务名称
    CLUSTER_SVR_NAME = {
        USER = "usernode",
        ROBOT = "robotnode"
    },
    
    -- 房间类型
    ROOM_TYPE = {
        MATCH = 1,     -- 匹配房间
        PRIVATE = 2    -- 私人房间
    },
    
    -- 用户状态
    USER_STATUS = {
        FREE = 0,      -- 空闲
        MATCHING = 1,  -- 匹配中
        GAMEING = 2    -- 游戏中
    }
}
```

## Games服务配置

### 主配置文件 (src/services/games/config.lua)

```lua
local config = {
    -- 支持的游戏ID列表
    gameids = {10001, 10002}
}

return config
```

**配置说明**:
- `gameids`: 数组，定义服务支持的所有游戏类型
- 新增游戏时需要在此处添加对应的游戏ID

## 游戏特定配置

### 游戏10001配置 (src/services/games/10001/config.lua)

```lua
local config = {
    -- 房间等待时间配置
    MATCH_ROOM_WAITTING_CONNECT_TIME = 8,      -- 匹配房间等待连接时间(秒)
    MATCH_ROOM_GAME_TIME = 900,                -- 匹配房间游戏时间(秒)
    PRIVATE_ROOM_WAITTING_CONNECT_TIME = 7200, -- 私人房间等待连接时间(秒)
    PRIVATE_ROOM_GAME_TIME = 7200,             -- 私人房间游戏时间(秒)
    
    -- 游戏状态枚举
    GAME_STATUS = {
        NONE = 0,              -- 无状态
        WAITTING_CONNECT = 1,  -- 等待连接
        START = 2,             -- 游戏开始
        END = 3                -- 游戏结束
    },
    
    -- 玩家状态枚举
    PLAYER_STATUS = {
        LOADING = 1,   -- 加载中
        OFFLINE = 2,   -- 离线
        ONLINE = 3,    -- 在线
        PLAYING = 4,   -- 游戏中
        READY = 5      -- 准备
    },
    
    -- 日志类型枚举
    LOG_TYPE = {
        CREATE_ROOM = 0,   -- 创建房间
        DESTROY_ROOM = 1,  -- 销毁房间
        GAME_START = 2,    -- 游戏开始
        GAME_END = 3,      -- 游戏结束
        GAME_RESULT = 4,   -- 游戏结果
    },
    
    -- 日志结果类型
    LOG_RESULT_TYPE = {
        GAME_END = 1,
    },
    
    -- 游戏结果类型
    RESULT_TYPE = {
        NONE = 0,   -- 无结果
        WIN = 1,    -- 胜利
        LOSE = 2,   -- 失败
        DRAW = 3,   -- 平局
        ESCAPE = 4, -- 逃跑
    },
    
    -- 协议配置
    SPROTO = {
        C2S = "game10001_c2s",  -- 客户端到服务端协议名
        S2C = "game10001_s2c",  -- 服务端到客户端协议名
    },
    
    -- 房间结束标志
    ROOM_END_FLAG = {
        NONE = 0,              -- 无
        GAME_END = 1,          -- 游戏结束
        OUT_TIME_WAITING = 2,  -- 等待超时
        OUT_TIME_PLAYING = 3,  -- 游戏超时
    },
    
    -- 座位标志
    SEAT_FLAG = {
        SEAT_ALL = 0,  -- 所有座位
    }
}

return config
```

### 配置参数详解

#### 时间配置

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| MATCH_ROOM_WAITTING_CONNECT_TIME | number | 8 | 匹配房间等待玩家连接的最大时间 |
| MATCH_ROOM_GAME_TIME | number | 900 | 匹配房间游戏进行的最大时间 |
| PRIVATE_ROOM_WAITTING_CONNECT_TIME | number | 7200 | 私人房间等待连接的最大时间 |
| PRIVATE_ROOM_GAME_TIME | number | 7200 | 私人房间游戏进行的最大时间 |

**配置建议**:
- 匹配房间时间较短，确保快速匹配体验
- 私人房间时间较长，适应朋友间的休闲游戏
- 根据游戏复杂度调整游戏时间

#### 状态枚举

**游戏状态 (GAME_STATUS)**:
- `NONE`: 房间初始状态，尚未开始游戏流程
- `WAITTING_CONNECT`: 等待玩家连接状态
- `START`: 游戏进行状态
- `END`: 游戏结束状态

**玩家状态 (PLAYER_STATUS)**:
- `LOADING`: 玩家正在加载游戏资源
- `OFFLINE`: 玩家离线状态
- `ONLINE`: 玩家在线但未准备
- `PLAYING`: 玩家正在游戏中
- `READY`: 玩家已准备开始游戏

#### 协议配置

```lua
SPROTO = {
    C2S = "game10001_c2s",  -- 客户端到服务端
    S2C = "game10001_s2c",  -- 服务端到客户端
}
```

协议名称对应`sharedata`中的键名，用于加载对应的sproto协议。

## 逻辑配置 (configLogic.lua)

### 游戏逻辑参数

```lua
local configLogic = {
    -- 游戏基础参数
    MAX_PLAYERS = 2,        -- 最大玩家数
    MIN_PLAYERS = 2,        -- 最小玩家数
    
    -- 回合配置
    MAX_ROUNDS = 3,         -- 最大轮数
    TURN_TIME_LIMIT = 30,   -- 每回合时间限制(秒)
    
    -- 分数配置
    WIN_SCORE = 100,        -- 获胜所需分数
    ACTION_SCORE = 10,      -- 每次行动基础分数
    BONUS_MULTIPLIER = 1.5, -- 奖励倍数
    
    -- AI配置
    AI_THINK_TIME = 2,      -- AI思考时间(秒)
    AI_DIFFICULTY = 2,      -- AI难度等级(1-3)
    
    -- 特殊规则
    ALLOW_UNDO = false,     -- 是否允许悔棋
    SHOW_OPPONENT = false,  -- 是否显示对手信息
    DOUBLE_SCORE = false,   -- 是否双倍计分
}

return configLogic
```

## 协议配置

### 协议文件结构

```
proto/
└── game10001/
    ├── c2s.sproto          -- 客户端到服务端协议
    └── s2c.sproto          -- 服务端到客户端协议
```

### C2S协议示例 (c2s.sproto)

```protobuf
.package {
    type 0 : integer
    session 1 : integer
}

# 玩家行动
playerAction 1 {
    request {
        action 0 : string       # 行动类型
        x 1 : integer          # X坐标
        y 2 : integer          # Y坐标
        params 3 : string      # 额外参数
    }
}

# 玩家准备
playerReady 2 {
    request {
        ready 0 : integer      # 1:准备, 0:取消准备
    }
}

# 聊天消息
chatMessage 3 {
    request {
        message 0 : string     # 聊天内容
        type 1 : integer       # 消息类型
    }
}
```

### S2C协议示例 (s2c.sproto)

```protobuf
.package {
    type 0 : integer
    session 1 : integer
}

# 游戏开始
gameStart 1 {
    request {
        roundNum 0 : integer    # 轮次编号
        startTime 1 : integer   # 开始时间戳
        roundData 2 : string    # 轮次数据
    }
}

# 游戏结束
gameEnd 2 {
    request {
        roundNum 0 : integer    # 轮次编号
        endTime 1 : integer     # 结束时间戳
        roundData 2 : string    # 结束数据
    }
}

# 行动结果
actionResult 3 {
    request {
        seat 0 : integer        # 玩家座位
        action 1 : string       # 行动类型
        result 2 : string       # 结果数据
        success 3 : integer     # 是否成功
    }
}

# 游戏状态同步
gameStateSync 4 {
    request {
        phase 0 : string        # 游戏阶段
        turn 1 : integer        # 当前回合
        activePlayer 2 : integer # 当前行动玩家
        timeLeft 3 : integer    # 剩余时间
        boardState 4 : string   # 棋盘状态
    }
}
```

## 环境配置

### 开发环境配置

```lua
-- 开发环境参数
if ENV == "development" then
    config.MATCH_ROOM_WAITTING_CONNECT_TIME = 3  -- 缩短等待时间便于测试
    config.AI_THINK_TIME = 0.5                   -- AI快速响应
    config.DEBUG_MODE = true                     -- 开启调试模式
end
```

### 生产环境配置

```lua
-- 生产环境参数
if ENV == "production" then
    config.DEBUG_MODE = false                    -- 关闭调试
    config.LOG_LEVEL = "INFO"                   -- 设置日志级别
    config.MAX_CONCURRENT_GAMES = 1000         -- 最大并发游戏数
end
```

## 配置热更新

### 热更新机制

```lua
-- 配置更新接口
function CMD.updateConfig(gameid, newConfig)
    local success, err = pcall(function()
        -- 验证配置格式
        if not validateConfig(newConfig) then
            error("Invalid config format")
        end
        
        -- 更新配置
        local configModule = "games." .. gameid .. ".config"
        package.loaded[configModule] = nil  -- 清除缓存
        local config = require(configModule)
        
        -- 通知所有房间更新配置
        for roomid, room in pairs(allGames[gameid] or {}) do
            skynet.send(room, "lua", "updateConfig", config)
        end
    end)
    
    return success, err
end
```

### 配置验证

```lua
function validateConfig(config)
    -- 检查必需字段
    local requiredFields = {
        "GAME_STATUS", "PLAYER_STATUS", "SPROTO"
    }
    
    for _, field in ipairs(requiredFields) do
        if not config[field] then
            return false, "Missing required field: " .. field
        end
    end
    
    -- 检查数值范围
    if config.MATCH_ROOM_WAITTING_CONNECT_TIME < 1 then
        return false, "Invalid waiting time"
    end
    
    return true
end
```

## 配置最佳实践

### 1. 配置分离

- 将环境相关配置与业务配置分离
- 使用配置文件而非硬编码
- 敏感配置使用环境变量

### 2. 版本管理

- 配置文件版本化管理
- 向下兼容旧版本配置
- 配置迁移脚本

### 3. 安全考虑

- 验证所有外部输入的配置
- 限制配置值的范围
- 记录配置更改日志

### 4. 性能优化

- 缓存频繁使用的配置
- 避免配置文件的重复加载
- 使用配置预编译

### 5. 监控告警

- 监控配置文件完整性
- 配置错误自动告警
- 配置变更审计日志

## 常见配置问题

### 1. 协议不匹配

**问题**: 客户端和服务端协议版本不一致
**解决**: 
```lua
-- 添加协议版本检查
SPROTO = {
    C2S = "game10001_c2s",
    S2C = "game10001_s2c",
    VERSION = "1.0.0"  -- 添加版本号
}
```

### 2. 超时时间设置

**问题**: 超时时间过短导致正常游戏被中断
**解决**: 根据游戏复杂度合理设置时间，提供配置调整接口

### 3. 状态枚举冲突

**问题**: 不同模块使用相同的状态值
**解决**: 使用命名空间分离不同模块的枚举

### 4. 配置热更新失效

**问题**: 修改配置后不生效
**解决**: 确保清除require缓存并重新加载配置模块