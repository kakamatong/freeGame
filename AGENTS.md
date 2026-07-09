# AGENTS.md

基于Skynet框架的Lua多玩家游戏服务器。集群架构，WebSocket通信，sproto协议。

## 构建

```bash
# 构建（必须先覆盖skynet的Makefile，build/Makefile增加了cjson和TLS支持）
cp build/Makefile skynet/Makefile && cd skynet && make

# 清理
cd skynet && make clean          # 清理构建产物
cd skynet && make cleanall       # 完全清理（含jemalloc/lua等依赖）
```

## 运行

```bash
./run.sh                          # 启动全部13个服务
./stop.sh                         # 停止全部（killall skynet）
./skynet/skynet config/configXXX  # 单独启动某服务（调试用）
sh/runXXX.sh / sh/stopXXX.sh     # 部分服务的独立启停脚本
```

## 架构要点

### 服务启动流程
`main.lua` → `db/server`（数据库）→ `clusterManager/server`（集群管理）→ 各业务服务注册上线

### 集群通信
所有跨服务通信通过 `clusterManager`，在 `src/preload.lua` 中注册为全局函数：
- `call(svr, cmd, ...)` — 同步调用
- `send(svr, cmd, ...)` — 异步发送
- `callTo(name, svr, cmd, ...)` / `sendTo(name, svr, cmd, ...)` — 指定节点
- `svr` 参数来自 `CONFIG.SVR_NAME` 或 `CONFIG.CLUSTER_SVR_NAME`

`clusterManager` 每2分钟从Redis拉取 `clusterConfig` 对比版本号，支持动态增减节点。

### 全局环境（preload.lua）
`src/preload.lua` 在每个Lua服务启动前执行，注册以下全局变量：
- `_G.CONFIG` — 来自 `gameConfig.lua`（**注意：此文件在 .gitignore 中**，仓库内为示例，生产配置另存）
- `_G.UTILS` — deepcopy, table_merge, string_split, tableToString
- `_G.STAT` — timing_start/end, counter_inc（性能统计）
- `_G.call/send/callTo/sendTo` — 集群通信

### 玩家连接流程
客户端 → `wsLogind` (DH密钥交换+加密token) → 认证 → `wsGate` (分配agent) → `agent.lua` 处理业务请求

游戏内连接：
客户端 → `wsGameGate` (认证+连接房间) → 游戏房间服务

### WebSocket端口
| 服务 | 端口 | 用途 |
|------|------|------|
| Login | 8002 | 登录认证 |
| Gate | 9002 | 大厅网关 |
| Gate2 | 9005 | 第二大厅网关 |
| Game | 9003 | 游戏网关(nodeid=1) |
| Game2 | 9006 | 游戏网关(nodeid=2, hide) |
| Web | 9020 | HTTP管理 |

## 数据库

通过 `db/server.lua` 统一访问，使用全局通信：
```lua
call(svrDB, "dbRedis", "set", key, value, expire)
call(svrDB, "dbRedis", "get", key)
call(svrDB, "dbMySQL", "query", sql, ...)
```

数据库服务在 `main.lua` 中第一个启动（其他服务依赖它）。

## 配置

`src/config/gameConfig.lua`（gitignored，仓库内为模板示例）定义：
- MySQL/Redis 连接
- `SVR_NAME`（本地服务名，前缀 `.`）
- `CLUSTER_SVR_NAME`（集群名）
- `USER_STATUS`（0离线~8进入游戏）
- `ROOM_TYPE`（0匹配/1私人）
- `RICH_TYPE`（货币/道具类型）
- `TOKEN_EXPIRE`、`PRIVATE_ROOM_SHORTID_TIME` 等

每个服务的配置文件在 `config/` 下，通过 `include "config.path"` 加载路径，再覆盖端口、clusterName、nodeid等。

## 协议

`sproto` 格式，位于 `proto/`。每类协议有 `c2s.sproto` 和 `s2c.sproto`：
- `proto/lobby/` — 大厅协议
- `proto/game10001/`、`proto/game10002/` — 各游戏协议

修改 sproto 后仅需重启服务，无需重新构建Skynet。

## 添加新游戏

三处修改：
1. `src/services/games/config.lua` — 在 `gameids` 表注册游戏ID
2. `proto/game{gameid}/` — 添加 c2s.sproto 和 s2c.sproto
3. `src/services/games/{gameid}/` — 添加 room.lua、logic.lua、config.lua 等

## 代码约定

### 响应格式（必须遵守）
```lua
return {code = 1, msg = "Success", data = result}   -- 成功
return {code = 0, msg = "Error description"}         -- 失败
```

### 服务模式
```lua
local CMD = {}
function CMD.someMethod(args)
    -- 处理逻辑
    return {code = 1, data = result}
end
```

### 注释规范
- 接口函数和新增的全局变量必须有注释（说明用途、参数、返回值）
- 核心/复杂逻辑必须有注释（解释算法思路、边界条件、为什么这样写）
- 每个模块文件头部必须有模块注释（简述模块职责和主要功能）

### 关键约束
- 使用 `skynet.timeout()` 做延迟，**禁止** `sleep()` 或阻塞操作
- 始终用 `pcall` 包裹可能失败的外部调用
- 文件命名 snake_case，构造函数 PascalCase，常量 UPPER_SNAKE_CASE
- 服务内 `agent.lua` 中客户端请求处理函数放在 `REQUEST` 表下

## 文档

`docs/games/` 目录有详细的架构、API、房间管理、部署、故障排除等文档（中文）。
