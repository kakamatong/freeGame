# Games服务API接口文档

## 概述

Games服务提供房间管理、游戏逻辑处理的核心API接口。所有接口基于Skynet的lua协议进行通信。

## 服务接口 (server.lua)

### 1. 创建匹配房间

**接口名称**: `createMatchGameRoom`

**描述**: 创建匹配类型的游戏房间

**参数**:
- `gameid` (number): 游戏ID
- `players` (table): 玩家ID列表，按座位顺序排列
- `gameData` (table): 游戏数据配置

**返回值**:
- `roomid` (number): 房间ID（雪花算法生成）
- `addr` (string): 服务地址

**示例**:
```lua
local roomid, addr = skynet.call(gamesService, "lua", "createMatchGameRoom", 10001, {1001, 1002}, {
    rule = "default",
    robots = {1002} -- 1002为机器人
})
```

### 2. 创建私人房间

**接口名称**: `createPrivateGameRoom`

**描述**: 创建私人类型的游戏房间

**参数**:
- `gameid` (number): 游戏ID
- `players` (table): 玩家ID列表，第一个为房主
- `gameData` (table): 游戏数据配置

**返回值**:
- `roomid` (number): 房间ID（雪花算法生成）
- `addr` (string): 服务地址
- `shortRoomid` (number): 短房间号（6位数字）

**示例**:
```lua
local roomid, addr, shortRoomid = skynet.call(gamesService, "lua", "createPrivateGameRoom", 10001, {1001}, {
    rule = '{"playerCnt":2,"battleCnt":1}',
    battleCnt = 1
})
```

### 3. 加入私人房间

**接口名称**: `joinPrivateRoom`

**描述**: 玩家加入已存在的私人房间

**参数**:
- `gameid` (number): 游戏ID
- `roomid` (number): 房间ID
- `userid` (number): 用户ID

**返回值**:
- `success` (boolean): 加入是否成功
- `message` (string): 错误信息（失败时）

**示例**:
```lua
local success, message = skynet.call(gamesService, "lua", "joinPrivateRoom", 10001, roomid, 1002)
```

### 4. 销毁房间

**接口名称**: `destroyGame`

**描述**: 销毁指定的游戏房间

**参数**:
- `gameid` (number): 游戏ID
- `roomid` (number): 房间ID

**返回值**:
- `success` (boolean): 销毁是否成功

**示例**:
```lua
local success = skynet.call(gamesService, "lua", "destroyGame", 10001, roomid)
```

### 5. 检查房间存在

**接口名称**: `checkHaveRoom`

**描述**: 检查指定房间是否存在

**参数**:
- `gameid` (number): 游戏ID
- `roomid` (number): 房间ID

**返回值**:
- `exists` (boolean): 房间是否存在

**示例**:
```lua
local exists = skynet.call(gamesService, "lua", "checkHaveRoom", 10001, roomid)
```

## 房间接口 (BaseRoom)

### 1. 启动房间

**接口名称**: `start`

**描述**: 初始化并启动房间服务

**参数**:
- `roomData` (table): 房间初始化数据

**房间数据结构**:
```lua
{
    gameid = 10001,
    players = {1001, 1002},
    gameData = {
        rule = "游戏规则",
        battleCnt = 1,
        robots = {1002}
    },
    roomid = 123456789,
    addr = "game_server_1",
    gameManager = skynet_service_address,
    roomType = 1, -- 1:匹配房间, 2:私人房间
    shortRoomid = 123456 -- 私人房间短号
}
```

### 2. 玩家连接

**接口名称**: `connect`

**描述**: 处理玩家连接到房间

**参数**:
- `userid` (number): 用户ID
- `fd` (number): 连接文件描述符

**返回值**:
- `result` (table): 连接结果

### 3. 玩家断线

**接口名称**: `disconnect`

**描述**: 处理玩家从房间断线

**参数**:
- `userid` (number): 用户ID

### 4. 玩家重连

**接口名称**: `relink`

**描述**: 处理玩家重连到房间

**参数**:
- `userid` (number): 用户ID
- `fd` (number): 新的连接文件描述符

### 5. 处理客户端消息

**接口名称**: `onClientData`

**描述**: 处理来自客户端的游戏消息

**参数**:
- `fd` (number): 连接文件描述符
- `msg` (string): 消息内容

## 私人房间接口 (PrivateRoom)

### 1. 加入私人房间

**接口名称**: `joinPrivateRoom`

**描述**: 玩家加入私人房间

**参数**:
- `userid` (number): 用户ID

**返回值**:
- `success` (boolean): 是否成功
- `message` (string): 错误信息

### 2. 离开房间

**接口名称**: `leaveRoom`

**描述**: 玩家离开私人房间

**参数**:
- `userid` (number): 用户ID

**返回值**:
```lua
{
    code = 1, -- 1:成功, 0:失败
    msg = "操作结果描述"
}
```

### 3. 游戏准备

**接口名称**: `gameReady`

**描述**: 玩家准备/取消准备游戏

**参数**:
- `userid` (number): 用户ID
- `ready` (number): 1:准备, 0:取消准备

**返回值**:
```lua
{
    code = 1, -- 1:成功, 0:失败
    msg = "操作结果描述"
}
```

## 游戏逻辑接口 (Logic)

### 1. 游戏开始

**消息名称**: `gameStart`

**发送对象**: 所有玩家或指定玩家

**消息内容**:
```lua
{
    roundNum = 1,      -- 轮次编号
    startTime = 1234567890, -- 开始时间戳
    roundData = ""     -- 轮次数据
}
```

### 2. 游戏结束

**消息名称**: `gameEnd`

**发送对象**: 所有玩家或指定玩家

**消息内容**:
```lua
{
    roundNum = 1,      -- 轮次编号
    endTime = 1234567890,   -- 结束时间戳
    roundData = ""     -- 结束数据
}
```

### 3. 玩家行动

**消息名称**: 根据具体游戏定义

**处理方式**: 通过协议解析后调用对应的逻辑处理函数

## AI接口 (AI)

### 1. AI消息处理

**接口名称**: `onAiMsg`

**描述**: 处理AI机器人的游戏行为

**参数**:
- `seat` (number): AI座位号
- `name` (string): 消息名称
- `data` (table): 消息数据

## 错误码定义

### 房间操作错误码
- `0`: 操作失败
- `1`: 操作成功

### 玩家状态码
```lua
PLAYER_STATUS = {
    LOADING = 1,   -- 加载中
    OFFLINE = 2,   -- 离线
    ONLINE = 3,    -- 在线
    PLAYING = 4,   -- 游戏中
    READY = 5      -- 准备
}
```

### 房间状态码
```lua
GAME_STATUS = {
    NONE = 0,              -- 无状态
    WAITTING_CONNECT = 1,  -- 等待连接
    START = 2,             -- 游戏开始
    END = 3                -- 游戏结束
}
```

## 使用示例

### 完整的房间创建和游戏流程

```lua
-- 1. 创建私人房间
local roomid, addr, shortRoomid = skynet.call(gamesService, "lua", "createPrivateGameRoom", 
    10001, 
    {1001}, 
    {
        rule = '{"playerCnt":2}',
        battleCnt = 1
    }
)

-- 2. 其他玩家加入房间
local success, msg = skynet.call(gamesService, "lua", "joinPrivateRoom", 10001, roomid, 1002)

-- 3. 玩家连接到房间
skynet.call(roomService, "lua", "connect", 1001, fd1)
skynet.call(roomService, "lua", "connect", 1002, fd2)

-- 4. 玩家准备游戏
skynet.call(roomService, "lua", "gameReady", 1001, 1)
skynet.call(roomService, "lua", "gameReady", 1002, 1)

-- 5. 游戏自动开始，处理游戏消息
-- 客户端发送游戏操作消息
-- 服务端处理并广播结果

-- 6. 游戏结束，房间自动销毁
```

## 注意事项

1. **线程安全**: 所有房间操作都在独立的Skynet服务中执行，确保线程安全
2. **内存管理**: 房间销毁时会自动清理所有相关资源
3. **协议版本**: 确保客户端和服务端使用相同版本的Sproto协议
4. **超时处理**: 房间会自动检测超时情况并进行清理
5. **日志记录**: 所有重要操作都会记录到数据库日志中