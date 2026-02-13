# 连连看房间生命周期流程图 (room.lua)

## 1. 房间模块概述

**继承关系**: `Room` → `PrivateRoom` → `BaseRoom`

**职责**:
- 房间管理（创建、初始化、销毁）
- 玩家连接管理（连接、重连、断开）
- 生命周期管理（匹配房/私人房不同逻辑）
- 游戏逻辑委托（通过 `logicHandler` 调用 logic.lua）

---

## 2. 房间生命周期流程

```
┌─────────────────────────────────────────────────────────────────┐
│                        房间生命周期总览                          │
└─────────────────────────────────────────────────────────────────┘

创建房间
    │
    ▼
初始化(init)
    │
    ├─▶ 匹配房间 ──▶ 等待连接 ──▶ 开始游戏 ──▶ 游戏中 ──▶ 结束
    │                    │            │           │
    │                    │            │           └─▶ 单局结束
    │                    │            │                    │
    │                    │            │                    ├─▶ [匹配房] 结束房间
    │                    │            │                    └─▶ [私人房] 局间休息
    │                    │            │                             │
    │                    │            │                             ▼
    │                    │            │                        等待准备
    │                    │            │                             │
    │                    │            │                             ▼
    │                    │            └────────────────────────── 开始下一局
    │                    │
    │                    └─▶ 断开检测 ──▶ 超时处理
    │
    └─▶ 私人房间 ──▶ 等待连接 ──▶ 准备阶段 ──▶ 开始游戏 ──▶ 游戏中
                                         │                        │
                                         │                        ▼
                                         │                   检查局数
                                         │                        │
                                         │            ┌──────────┴──────────┐
                                         │            │                     │
                                         │            ▼                     ▼
                                         │      还有下一局               最后一局
                                         │            │                     │
                                         │            ▼                     ▼
                                         │      局间休息 ──▶ 准备      房间结束
                                         │            │                     │
                                         └────────────┴─────────────────────┘
```

---

## 3. 详细生命周期流程

### 3.1 房间创建与初始化

```
服务启动(skynet.start)
    │
    ▼
CMD.start(data)
    │
    ├─▶ Room:new()
    │       │
    │       ├─▶ PrivateRoom:new() [父类构造函数]
    │       │
    │       └─▶ _initRoom()
    │               │
    │               ├─▶ 设置 config
    │               ├─▶ 设置 logicHandler
    │               └─▶ 设置定时器间隔 dTime = 100
    │
    └─▶ roomInstance:init(data)
            │
            ├─▶ PrivateRoom.init(self, data) [父类初始化]
            │
            ├─▶ 房间类型判断
            │       │
            │       ├─▶ [匹配房] isMatchRoom()
            │       │       │
            │       │       ├─▶ 设置 playerNum
            │       │       ├─▶ 设置 nowPlayerNum
            │       │       ├─▶ 设置 roomWaitingConnectTime (30秒)
            │       │       ├─▶ 设置 roomGameTime (600秒)
            │       │       └─▶ _initMatchRoomPlayers(data)
            │       │               │
            │       │               ├─▶ 识别机器人
            │       │               ├─▶ 设置玩家状态 (LOADING/READY)
            │       │               ├─▶ 设置用户全局状态 (GAMEING)
            │       │               └─▶ checkUserInfo()
            │       │
            │       └─▶ [私人房] isPrivateRoom()
            │               │
            │               └─▶ 加载模式配置 (modeData)
            │                       │
            │                       ├─▶ name: "单局竞速"
            │                       ├─▶ maxCnt: 1 [最大局数]
            │                       └─▶ winCnt: 1 [胜利局数]
            │
            ├─▶ roomStatus = WAITTING_CONNECT
            │
            ├─▶ loadSproto() [加载协议]
            │
            ├─▶ startTimer() [启动定时器]
            │       │
            │       └─▶ skynet.fork()
            │               │
            │               ├─▶ 每100ms循环
            │               ├─▶ logicHandler.update() [游戏逻辑更新]
            │               └─▶ checkRoomTimeout() [房间超时检查]
            │
            ├─▶ pushLog(CREATE_ROOM) [记录创建日志]
            │
            └─▶ testStart() [检查是否可开始]
```

### 3.2 匹配房间连接流程

```
玩家连接(connectGame)
    │
    ▼
CMD.connectGame(userid, client_fd)
    │
    ├─▶ roomInstance:connectGame(userid, client_fd)
    │       │
    │       ├─▶ [继承自 PrivateRoom/BaseRoom]
    │       ├─▶ 验证玩家是否在房间列表中
    │       ├─▶ 设置玩家 socket fd
    │       ├─▶ 更新玩家状态为 ONLINE
    │       └─▶ 发送房间信息给客户端
    │
    └─▶ 检查是否所有玩家都已连接
            │
            └─▶ 是 → 触发游戏开始流程
```

### 3.3 私人房间加入流程

```
玩家加入(joinPrivateRoom)
    │
    ▼
CMD.joinPrivateRoom(userid)
    │
    ├─▶ roomInstance:joinPrivateRoom(userid)
    │       │
    │       ├─▶ [继承自 PrivateRoom]
    │       ├─▶ 检查房间是否已满
    │       ├─▶ 分配座位号
    │       ├─▶ 添加玩家到房间
    │       └─▶ 广播玩家加入消息
    │
    └─▶ 等待房主开始游戏
```

### 3.4 游戏开始流程

```
开始游戏(startGame)
    │
    ▼
Room:startGame() [重写父类方法]
    │
    ├─▶ roomStatus = START
    │
    ├─▶ playedCnt += 1
    │
    ├─▶ gameStartTime = os.time()
    │
    ├─▶ initLogic() [初始化游戏逻辑]
    │       │
    │       ├─▶ 设置规则数据
    │       │       ├─▶ playerCnt: 玩家数量
    │       │       ├─▶ mapRows: 默认8行
    │       │       ├─▶ mapCols: 默认12列
    │       │       └─▶ iconTypes: 图标种类数
    │       │
    │       └─▶ logicHandler.init(ruleData, roomHandler)
    │               │
    │               └─▶ [详见 logic_flow.md 初始化流程]
    │
    ├─▶ logicHandler.startGame(playedCnt)
    │       │
    │       └─▶ [详见 logic_flow.md 游戏开始流程]
    │
    ├─▶ 更新所有玩家状态为 PLAYING
    │
    ├─▶ [私人房] 初始化本局记录
    │       │
    │       ├─▶ record[playedCnt] = {index, startTime}
    │       └─▶ sendAllPrivateInfo()
    │
    └─▶ pushLog(GAME_START) [记录开始日志]
```

### 3.5 游戏中流程

```
游戏中状态
    │
    ├─▶ 定时器循环 [每100ms]
    │       │
    │       ├─▶ logicHandler.update()
    │       │       │
    │       │       └─▶ [详见 logic_flow.md 更新流程]
    │       │               ├─▶ 检查阶段超时
    │       │               └─▶ 触发超时处理
    │       │
    │       └─▶ checkRoomTimeout()
    │               │
    │               └─▶ 检查房间超时
    │                       ├─▶ 等待连接超时
    │                       └─▶ 游戏总时长超时
    │
    ├─▶ 处理客户端请求(request)
    │       │
    │       ├─▶ clickTiles [点击消除]
    │       │       │
    │       │       ├─▶ 获取玩家座位号
    │       │       └─▶ logicHandler.clickTiles(seat, args)
    │       │               │
    │       │               └─▶ [详见 logic_flow.md 消除流程]
    │       │
    │       ├─▶ clientReady [客户端准备]
    │       │
    │       ├─▶ gameReady [游戏准备]
    │       │
    │       ├─▶ leaveRoom [离开房间]
    │       │
    │       ├─▶ voteDisbandRoom [发起投票解散]
    │       │
    │       └─▶ voteDisbandResponse [投票响应]
    │
    └─▶ 重连处理(relink)
            │
            ├─▶ 获取玩家座位号
            └─▶ logicHandler.relink(seat)
                    │
                    └─▶ [详见 logic_flow.md 重连流程]
```

### 3.6 单局结束流程

```
单局结束(roomHandler.onGameEnd)
    │
    ├─▶ 记录本局战绩
    │       │
    │       └─▶ record[currentRound].endTime = os.time()
    │           record[currentRound].rankings = rankings
    │
    ├─▶ 房间类型判断
            │
            ├─▶ [匹配房] ──▶ roomEnd(GAME_END)
            │                      │
            │                      └─▶ [继承方法] 结束房间
            │
            └─▶ [私人房]
                    │
                    ├─▶ 检查是否还有下一局
                    │       │
                    │       ├─▶ currentRound < mode.maxCnt?
                    │       │       │
                    │       │       ├─▶ 是 → 进入局间休息
                    │       │       │       │
                    │       │       │       ├─▶ roomStatus = HALFTIME
                    │       │       │       ├─▶ 重置玩家状态为 ONLINE
                    │       │       │       ├─▶ sendToAll("roundEnd", {...})
                    │       │       │       │
                    │       │       │       └─▶ [等待玩家准备]
                    │       │       │               │
                    │       │       │               └─▶ gameReady(ready=true)
                    │       │       │                       │
                    │       │       │                       └─▶ testStart()
                    │       │       │                               │
                    │       │       │                               └─▶ 所有玩家准备?
                    │       │       │                                       │
                    │       │       │                                       ├─▶ 是 → startGame()
                    │       │       │                                       └─▶ 否 → 继续等待
                    │       │       │
                    │       │       └─▶ 否 → roomEnd(GAME_END)
                    │       │
                    │       └─▶ 结束房间
                    │
                    └─▶ [匹配房已处理]
```

### 3.7 房间结束流程

```
房间结束(roomEnd)
    │
    ▼
[继承自 PrivateRoom/BaseRoom]
    │
    ├─▶ 保存游戏记录到数据库
    │
    ├─▶ 更新所有玩家状态为在线
    │
    ├─▶ 发送房间结束消息给所有玩家
    │
    ├─▶ 清理房间数据
    │
    └─▶ 通知上层服务房间已关闭
```

### 3.8 异常处理流程

```
异常处理
    │
    ├─▶ 玩家断开连接(socketClose)
    │       │
    │       └─▶ CMD.socketClose(fd)
    │               │
    │               └─▶ roomInstance:socketClose(fd)
    │                       │
    │                       ├─▶ [继承方法] 更新玩家状态
    │                       └─▶ 检查是否需解散房间
    │
    ├─▶ 房间停止(stop)
    │       │
    │       └─▶ CMD.stop()
    │               │
    │               └─▶ roomInstance:stop()
    │                       │
    │                       └─▶ [继承方法] 清理资源
    │
    └─▶ 投票解散
            │
            ├─▶ voteDisbandRoom(userid, reason)
            │       │
            │       └─▶ [继承方法] 发起投票
            │
            └─▶ voteDisbandResponse(userid, voteId, agree)
                    │
                    └─▶ [继承方法] 处理投票结果
                            │
                            └─▶ 投票通过?
                                    │
                                    ├─▶ 是 → roomEnd(VOTE_DISBAND)
                                    └─▶ 否 → 继续游戏
```

---

## 4. Room → Logic 通信接口

```lua
roomHandler = {
    -- 发送消息给指定座位
    sendToSeat(seat, name, data)
        └─▶ roomInstance:sendToOneClient(userid, name, data)
    
    -- 广播消息给所有玩家
    sendToAll(name, data)
        └─▶ roomInstance:sendToAllClient(name, data)
    
    -- 玩家完成游戏回调
    onPlayerFinish(seat, usedTime, rank)
        └─▶ 记录日志
    
    -- 单局游戏结束回调
    onGameEnd(endType, rankings)
        └─▶ 记录战绩 → 判断是否继续下一局
    
    -- 获取游戏时间
    getGameTime()
        └─▶ os.time() - gameStartTime
}
```

---

## 5. 房间状态流转

```
┌─────────────────────────────────────────────────────────────────┐
│                        房间状态机                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   NONE ──▶ WAITTING_CONNECT ──▶ START ──▶ HALFTIME ──▶ END    │
│                  │                │           │                 │
│                  │                │           │                 │
│                  ▼                ▼           ▼                 │
│              等待玩家连接      游戏进行中   局间休息            │
│                                                                 │
│   状态说明:                                                      │
│   ├─▶ NONE: 初始状态                                            │
│   ├─▶ WAITTING_CONNECT: 等待玩家连接                            │
│   ├─▶ START: 游戏开始                                           │
│   ├─▶ HALFTIME: 局间休息 (仅私人房多局模式)                      │
│   └─▶ END: 房间结束                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. 玩家状态流转

```
┌─────────────────────────────────────────────────────────────────┐
│                        玩家状态机                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   NONE ──▶ LOADING ──▶ ONLINE ──▶ READY ──▶ PLAYING ──▶ OFFLINE│
│              │           │           │          │               │
│              │           │           │          │               │
│              └───────────┴───────────┴──────────┘               │
│                                                                 │
│   状态说明:                                                      │
│   ├─▶ NONE: 初始状态                                            │
│   ├─▶ LOADING: 正在加载 (机器人直接为 READY)                     │
│   ├─▶ ONLINE: 在线但未准备                                        │
│   ├─▶ READY: 已准备就绪                                          │
│   ├─▶ PLAYING: 游戏中                                            │
│   └─▶ OFFLINE: 离线                                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. 客户端请求接口

| 请求名 | 说明 | 处理流程 |
|--------|------|----------|
| `clientReady` | 客户端准备完成 | 转发给父类处理 |
| `gameReady` | 游戏准备/取消准备 | 转发给父类处理，检查是否全部准备则开始游戏 |
| `leaveRoom` | 离开房间 | 转发给父类处理 |
| `voteDisbandRoom` | 发起投票解散 | 转发给父类处理 |
| `voteDisbandResponse` | 响应投票解散 | 转发给父类处理 |
| `clickTiles` | 点击消除 | 获取座位号 → 转发给 logicHandler.clickTiles() |

---

## 8. 服务端命令接口 (CMD)

| 命令 | 说明 |
|------|------|
| `start` | 初始化房间 |
| `connectGame` | 玩家连接游戏 |
| `joinPrivateRoom` | 玩家加入私人房 |
| `stop` | 停止房间 |
| `socketClose` | 处理 socket 关闭 |

---

## 9. 配置参数

### 9.1 匹配房间配置
```lua
MATCH_ROOM_WAITTING_CONNECT_TIME = 30  -- 等待连接超时时间(秒)
MATCH_ROOM_GAME_TIME = 600              -- 游戏总时长(秒)
```

### 9.2 私人房间模式配置
```lua
PRIVATE_ROOM_MODE = {
    [0] = {name = "单局竞速", maxCnt = 1, winCnt = 1},
    -- 可扩展其他模式
}
```

### 9.3 地图配置
```lua
MAP = {
    DEFAULT_ROWS = 8,    -- 默认行数
    DEFAULT_COLS = 12,   -- 默认列数
    ICON_TYPES = 8,      -- 图标种类数
}
```

---

## 10. 核心类图

```
┌─────────────────────────────────────────────────────────────────┐
│                           BaseRoom                              │
├─────────────────────────────────────────────────────────────────┤
│ - roomInfo: table                                               │
│ - players: table                                                │
│ - gConfig: table                                                │
├─────────────────────────────────────────────────────────────────┤
│ + init(data)                                                    │
│ + connectGame(userid, fd)                                       │
│ + socketClose(fd)                                               │
│ + roomEnd(flag)                                                 │
│ + stop()                                                        │
│ + sendToAllClient(name, data)                                   │
│ + sendToOneClient(userid, name, data)                           │
└─────────────────────────────────────────────────────────────────┘
                              △
                              │继承
                              │
┌─────────────────────────────────────────────────────────────────┐
│                         PrivateRoom                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ + joinPrivateRoom(userid)                                       │
│ + gameReady(userid, ready)                                      │
│ + clientReady(userid, args)                                     │
│ + leaveRoom(userid)                                             │
│ + voteDisbandRoom(userid, reason)                               │
│ + voteDisbandResponse(userid, voteId, agree)                    │
│ + isPrivateRoom()                                               │
│ + isMatchRoom()                                                 │
└─────────────────────────────────────────────────────────────────┘
                              △
                              │继承
                              │
┌─────────────────────────────────────────────────────────────────┐
│                     Room (10002)                                │
├─────────────────────────────────────────────────────────────────┤
│ - config: table                                                 │
│ - logicHandler: table                                           │
│ - dTime: number (100ms)                                         │
├─────────────────────────────────────────────────────────────────┤
│ + new()                                                         │
│ + _initRoom()                                                   │
│ + init(data)                                                    │
│ + _initMatchRoomPlayers(data)                                   │
│ + initLogic()                                                   │
│ + startTimer()                                                  │
│ + startGame()                                                   │
│ + relink(userid)                                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11. 流程总结

```
┌─────────────────────────────────────────────────────────────────┐
│                    房间生命周期关键节点                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 创建房间 (CMD.start)                                        │
│     └─▶ 初始化所有配置和定时器                                  │
│                                                                 │
│  2. 等待连接 (WAITTING_CONNECT)                                 │
│     ├─▶ [匹配房] 等待玩家自动连接                               │
│     └─▶ [私人房] 等待玩家加入并准备                             │
│                                                                 │
│  3. 开始游戏 (START)                                            │
│     ├─▶ 初始化游戏逻辑 (logicHandler.init)                      │
│     └─▶ 启动单局游戏 (logicHandler.startGame)                   │
│                                                                 │
│  4. 游戏中 (游戏中状态)                                         │
│     ├─▶ 定时更新逻辑 (logicHandler.update)                      │
│     ├─▶ 处理消除请求 (logicHandler.clickTiles)                  │
│     └─▶ 处理重连 (logicHandler.relink)                          │
│                                                                 │
│  5. 单局结束 (roomHandler.onGameEnd)                            │
│     ├─▶ [匹配房] 直接结束房间                                   │
│     └─▶ [私人房] 判断是否需要下一局                             │
│                                                                 │
│  6. 房间结束 (roomEnd)                                          │
│     └─▶ 保存记录、清理资源、通知上层                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```
