# 连连看游戏逻辑流程图 (logic.lua)

## 1. 游戏逻辑模块概述

**职责**: 管理一局游戏的生命周期（地图生成、消除逻辑、胜负判定）

**核心特点**:
- 只负责单局游戏，多局管理由 Room 控制
- 每局开始时 Room 会重新调用 `init()` 初始化
- 通过 `roomHandler` 与 Room 通信

---

## 2. 游戏阶段流程

```
┌─────────────────────────────────────────────────────────────────┐
│                        游戏阶段流转                              │
└─────────────────────────────────────────────────────────────────┘

[NONE] ──▶ [START] ──▶ [PLAYING] ──▶ [END]
   │          │            │            │
   │          │            │            │
   ▼          ▼            ▼            ▼
  初始化    1秒超时      玩家完成      游戏结束
           或强制进入   或时间耗尽     结算
```

### 2.1 START 阶段 (1秒)

```
startStep(START)
    │
    ▼
setStepBeginTime() ──────┐
    │                    │
    ▼                    │
logic.stepId = START     │
    │                    │
    ▼                    │
sendToAll("stepId", 1)   │
    │                    │
    ▼                    │
startStepStart() ◀───────┘
    │
    ├─▶ _generatePlayerMaps()
    │       │
    │       ▼
    │   mapGenerator.generate(rows, cols, icons)
    │       │
    │       ▼
    │   为每个座位创建 Map 实例
    │   初始化 playerProgress
    │
    ├─▶ 下发地图数据给每个玩家
    │   sendToSeat(seat, "mapData", {...})
    │   sendToSeat(seat, "progressUpdate", {...})
    │
    ▼
[等待1秒超时]
    │
    ▼
onStepStartTimeout()
    │
    ▼
stopStep(START) ──▶ startStep(PLAYING)
```

### 2.2 PLAYING 阶段 (可配置，默认600秒)

```
startStep(PLAYING)
    │
    ▼
setStepBeginTime()
    │
    ▼
logic.stepId = PLAYING
    │
    ▼
sendToAll("stepId", 2)
    │
    ▼
startStepPlaying()
    │
    ▼
sendToAll("gameClock", {time: maxTime})
    │
    ▼
[玩家进行消除操作]
    │
    ├─▶ clickTiles(seat, args)
    │       │
    │       ├─▶ 检查当前阶段是否为 PLAYING
    │       ├─▶ 检查玩家地图是否存在
    │       ├─▶ 检查玩家是否已完成
    │       ├─▶ 坐标转换 (客户端0-based → 服务端1-based)
    │       ├─▶ playerMap:removeTiles(p1, p2)
    │       │       │
    │       │       ├─▶ 检查两个方块是否可连接
    │       │       └─▶ 返回连接路径 (lines)
    │       │
    │       ├─▶ 更新进度 progress.eliminated += 2
    │       ├─▶ sendToSeat("tilesRemoved", {...})
    │       ├─▶ sendToAll("progressUpdate", {...})
    │       │
    │       └─▶ 检查是否完成
    │               │
    │               └─▶ playerMap:isComplete()
    │                       │
    │                       └─▶ _onPlayerFinish(seat)
    │                               │
    │                               ├─▶ 标记 finished = true
    │                               ├─▶ 计算用时 usedTime
    │                               ├─▶ 计算排名 rank
    │                               ├─▶ 检查是否第一个完成
    │                               │       │
    │                               │       └─▶ 设置10秒倒计时
    │                               │
    │                               ├─▶ roomHandler.onPlayerFinish()
    │                               ├─▶ sendToAll("playerFinished", {...})
    │                               │
    │                               └─▶ _checkGameEnd()
    │                                       │
    │                                       └─▶ 所有玩家完成?
    │                                               │
    │                                               ├─▶ 是 → stopStep(PLAYING)
    │                                               └─▶ 否 → 继续游戏
    │
    ▼
[定时检查超时]
    │
    ├─▶ update() [每帧调用]
    │       │
    │       └─▶ 检查阶段超时
    │               │
    │               └─▶ onStepPlayingTimeout()
    │                       │
    │                       └─▶ endGame(TIMEOUT)
    │
    ▼
[玩家全部完成或超时]
    │
    ▼
stopStep(PLAYING) ──▶ startStep(END)
```

### 2.3 END 阶段 (0秒)

```
startStep(END)
    │
    ▼
setStepBeginTime()
    │
    ▼
logic.stepId = END
    │
    ▼
sendToAll("stepId", 3)
    │
    ▼
startStepEnd()
    │
    ▼
[游戏结束处理已在 endGame() 中完成]
    │
    ▼
stopStep(END)
    │
    ▼
[通知 Room 本局结束]
```

---

## 3. 游戏结束流程

```
endGame(endType)
    │
    ├─▶ 检查是否已结束 (防止重复)
    ├─▶ 切换到 END 阶段
    ├─▶ logic.gameStatus = END
    │
    ├─▶ 计算最终排名
    │       │
    │       ├─▶ 遍历所有玩家进度
    │       ├─▶ 收集 {seat, usedTime, eliminated}
    │       └─▶ 按 usedTime 排序 (用时短在前)
    │
    ├─▶ sendToAll("gameEnd", {endType, rankings})
    ├─▶ sendToAll("progressUpdate", {...}) [每个玩家]
    │
    ├─▶ roomHandler.onGameEnd(endType, rankings)
    │       │
    │       └─▶ Room 处理房间结束或进入下一局
    │
    └─▶ stopStep(END)
```

---

## 4. 玩家重连流程

```
relink(seat)
    │
    ├─▶ 检查玩家数据是否存在
    │
    ├─▶ sendToSeat(seat, "stepId", {step: currentStep})
    ├─▶ sendToSeat(seat, "gameRelink", {startTime})
    ├─▶ sendToSeat(seat, "mapData", {mapData, totalBlocks})
    └─▶ sendToSeat(seat, "progressUpdate", {seat, eliminated, remaining, percentage, finished, usedTime})
```

---

## 5. 核心数据结构

### 5.1 游戏状态
```lua
logic = {
    playerMaps = {},      -- { [seat] = Map实例 }
    playerProgress = {},  -- { [seat] = { eliminated, startTime, finishTime, rank, finished } }
    roomHandler = nil,    -- Room 回调接口
    rule = {},            -- 游戏规则
    binit = false,        -- 是否初始化
    startTime = 0,        -- 游戏开始时间
    gameStatus = NONE,    -- 游戏状态
    stepId = NONE,        -- 当前阶段ID
    stepBeginTime = 0,    -- 阶段开始时间
    roundNum = 0,         -- 当前局数
}
```

### 5.2 Room 回调接口
```lua
roomHandler = {
    sendToSeat(seat, name, data),  -- 发送给指定座位
    sendToAll(name, data),          -- 广播给所有玩家
    onPlayerFinish(seat, usedTime, rank),  -- 玩家完成回调
    onGameEnd(endType, rankings),   -- 游戏结束回调
    getGameTime(),                  -- 获取游戏时间
}
```

---

## 6. 客户端协议消息

| 消息名 | 方向 | 说明 |
|--------|------|------|
| `stepId` | S→C | 阶段变更通知 |
| `gameStart` | S→C | 游戏开始通知 |
| `mapData` | S→C | 地图数据下发 |
| `progressUpdate` | S→C | 进度更新广播 |
| `gameClock` | S→C | 倒计时通知 |
| `tilesRemoved` | S→C | 消除成功通知 |
| `playerFinished` | S→C | 玩家完成通知 |
| `gameEnd` | S→C | 游戏结束通知 |
| `gameRelink` | S→C | 重连同步 |
| `clickTiles` | C→S | 点击消除请求 |

---

## 7. 结束类型

| 类型 | 说明 |
|------|------|
| `TIMEOUT` | 时间耗尽 |
| `ALL_FINISHED` | 所有玩家完成 |

---

## 8. 流程图总结

```
┌─────────────────────────────────────────────────────────────────┐
│                         核心流程                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   初始化(init)                                                  │
│      │                                                          │
│      ▼                                                          │
│   开始游戏(startGame) ──▶ START阶段 ──▶ PLAYING阶段 ──▶ END阶段 │
│                              │            │                      │
│                              │            ├─▶ 玩家消除          │
│                              │            ├─▶ 检查完成          │
│                              │            ├─▶ 计算排名          │
│                              │            └─▶ 超时检测          │
│                              │                                 │
│                              └─▶ 下发地图                      │
│                                                                 │
│   结束(endGame)                                                 │
│      ├─▶ 计算最终排名                                          │
│      ├─▶ 广播结果                                              │
│      └─▶ 通知 Room                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```
