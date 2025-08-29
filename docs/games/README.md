# Games服务文档

## 概览

Games服务是freeGame项目中的核心游戏逻辑处理模块，基于Skynet框架构建，负责游戏房间的创建、管理、销毁以及游戏逻辑的执行。

## 目录结构

```
docs/games/
├── README.md                    # 服务概览（本文件）
├── architecture.md              # 架构设计文档
├── api.md                      # API接口文档
├── room-management.md          # 房间管理文档
├── game-logic.md               # 游戏逻辑文档
├── configuration.md            # 配置说明文档
├── deployment.md               # 部署指南
└── troubleshooting.md          # 故障排除指南
```

## 核心功能

### 1. 房间管理
- 创建匹配房间和私人房间
- 房间生命周期管理
- 玩家加入/离开房间
- 房间状态监控

### 2. 游戏逻辑
- 支持多种游戏类型（当前支持游戏ID: 10001）
- 游戏状态管理
- 玩家行为处理
- AI机器人集成

### 3. 协议通信
- Sproto协议加载和管理
- 客户端/服务端消息处理
- 消息分发和路由

### 4. 数据持久化
- 游戏日志记录
- 玩家游戏记录
- 房间统计数据

## 服务架构

Games服务采用分层继承架构：

```
BaseRoom (基础房间类)
    ↓
PrivateRoom (私人房间类)
    ↓
Room (具体游戏实现)
```

## 主要组件

| 组件 | 文件路径 | 功能描述 |
|------|----------|----------|
| 服务管理器 | `src/services/games/server.lua` | 房间创建、销毁、管理 |
| 基础房间类 | `src/services/games/baseRoom.lua` | 房间基础功能和状态管理 |
| 私人房间类 | `src/services/games/privateRoom.lua` | 私人房间特有功能 |
| 游戏配置 | `src/services/games/config.lua` | 支持的游戏ID配置 |
| 具体游戏实现 | `src/services/games/10001/` | 游戏10001的具体实现 |

## 支持的游戏类型

当前支持的游戏：
- **游戏ID 10001**: 基础对战游戏，支持2人对战，包含AI机器人

## 房间类型

### 1. 匹配房间 (MATCH)
- 系统自动匹配玩家
- 游戏开始后不可离开
- 支持机器人填充

### 2. 私人房间 (PRIVATE)
- 玩家自主创建和管理
- 房主权限控制
- 灵活的加入/离开机制

## 快速开始

### 启动服务
```bash
# 启动games服务
./sh/runGame.sh
```

### 创建房间
```lua
-- 创建匹配房间
local roomid, addr = skynet.call(gamesService, "lua", "createMatchGameRoom", gameid, players, gameData)

-- 创建私人房间
local roomid, addr, shortRoomid = skynet.call(gamesService, "lua", "createPrivateGameRoom", gameid, players, gameData)
```

## 相关文档

- [架构设计](./architecture.md) - 详细的架构设计和继承关系
- [API接口](./api.md) - 完整的API接口文档
- [房间管理](./room-management.md) - 房间生命周期和管理机制
- [游戏逻辑](./game-logic.md) - 游戏逻辑处理和AI集成
- [配置说明](./configuration.md) - 配置文件详解
- [部署指南](./deployment.md) - 服务部署和运维
- [故障排除](./troubleshooting.md) - 常见问题和解决方案

## 版本信息

- 基于Skynet框架
- 支持Lua 5.3
- 协议格式：Sproto
- 通信方式：WebSocket