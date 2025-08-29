# Games服务故障排除指南

## 概述

本文档提供Games服务常见问题的诊断方法和解决方案，帮助开发者和运维人员快速定位和解决问题。

## 故障分类

### 1. 启动问题
- 服务无法启动
- 依赖库缺失
- 配置文件错误
- 端口冲突

### 2. 运行时问题
- 内存泄漏
- 连接超时
- 游戏逻辑错误
- AI行为异常

### 3. 性能问题
- 响应延迟高
- 并发处理能力不足
- 资源使用率异常

### 4. 网络问题
- 客户端连接失败
- 消息丢失
- 协议解析错误

## 诊断工具

### 1. 日志分析

#### 查看实时日志
```bash
# 查看Games服务日志
tail -f logs/game.log

# 查看错误日志
grep "ERROR" logs/game.log | tail -20

# 按时间过滤日志
grep "$(date +'%Y-%m-%d %H:%M')" logs/game.log
```

#### 日志级别说明
```
DEBUG: 详细调试信息
INFO:  一般信息记录
WARN:  警告信息
ERROR: 错误信息
FATAL: 致命错误
```

### 2. 进程监控

```bash
# 查看skynet进程
ps aux | grep skynet

# 查看进程详细信息
ps -p <pid> -o pid,ppid,cmd,pcpu,pmem,vsz,rss

# 查看进程线程
ps -T -p <pid>
```

### 3. 网络连接检查

```bash
# 查看服务端口状态
netstat -tlnp | grep 8001

# 查看连接数统计
netstat -an | grep :8001 | wc -l

# 查看具体连接
ss -tuln | grep 8001
```

### 4. 资源使用监控

```bash
# 查看内存使用
free -h

# 查看CPU使用率
top -p <skynet_pid>

# 查看磁盘IO
iostat -x 1

# 查看网络流量
iftop -i eth0
```

## 常见问题及解决方案

### 启动问题

#### 1. 服务无法启动 - "skynet not found"

**症状**：
```
Error: skynet not found, please compile first
```

**原因**：Skynet未编译或编译失败

**解决方案**：
```bash
# 进入skynet目录
cd skynet

# 清理并重新编译
make clean
make

# 检查编译结果
ls -la skynet
```

#### 2. 依赖库缺失 - "cjson module not found"

**症状**：
```
ERROR: module 'cjson' not found
```

**原因**：cjson模块未编译或路径不正确

**解决方案**：
```bash
# 编译cjson模块
cd skynet/3rd/lua-cjson
make

# 复制到正确位置
cp cjson.so ../../luaclib/

# 或修改Makefile自动处理
```

#### 3. 配置文件错误 - "config syntax error"

**症状**：
```
ERROR: config file syntax error at line 10
```

**原因**：配置文件语法错误

**解决方案**：
```bash
# 检查配置文件语法
lua -e "dofile('config/configGame')"

# 常见错误检查
# 1. 缺少逗号或分号
# 2. 字符串未正确引用
# 3. 路径分隔符错误
```

#### 4. 端口冲突 - "Address already in use"

**症状**：
```
ERROR: bind: Address already in use
```

**原因**：端口被其他进程占用

**解决方案**：
```bash
# 查找占用端口的进程
lsof -i :8001

# 杀死占用进程
kill -9 <pid>

# 或修改配置使用其他端口
```

### 运行时问题

#### 1. 内存泄漏

**症状**：
- 内存使用持续增长
- 系统变慢或崩溃

**诊断方法**：
```bash
# 监控内存使用趋势
while true; do
    ps -p <pid> -o pid,vsz,rss,pmem
    sleep 60
done

# 生成内存转储（如果支持）
kill -USR1 <skynet_pid>
```

**解决方案**：
```lua
-- 在房间销毁时清理资源
function BaseRoom:destroy()
    -- 清理玩家引用
    self.players = {}
    
    -- 清理定时器
    if self.timer then
        skynet.cancel(self.timer)
    end
    
    -- 清理循环引用
    self.logicHandler = nil
    self.aiHandler = nil
end
```

#### 2. 连接超时

**症状**：
- 客户端连接失败
- 连接建立后立即断开

**诊断方法**：
```bash
# 测试网络连接
telnet localhost 8001

# 检查防火墙
iptables -L

# 查看连接日志
grep "connect" logs/game.log
```

**解决方案**：
```lua
-- 增加连接超时时间
socket.timeout = 30

-- 添加连接重试机制
function retryConnect(host, port, maxRetries)
    for i = 1, maxRetries do
        local ok, err = pcall(skynet.connect, host, port)
        if ok then
            return true
        end
        skynet.sleep(100)  -- 等待1秒后重试
    end
    return false
end
```

#### 3. 游戏逻辑错误

**症状**：
- 游戏状态异常
- 玩家行为处理错误

**诊断方法**：
```lua
-- 添加调试日志
function logic.debug()
    log.debug("Game State: %s", UTILS.tableToString(logic.gameState))
    log.debug("Players: %s", UTILS.tableToString(logic.players))
end

-- 状态检查
function logic.validateState()
    assert(logic.gameState.phase, "Game phase not set")
    assert(logic.players, "Players not initialized")
end
```

**解决方案**：
```lua
-- 添加状态验证
function logic.onPlayerAction(seat, data)
    -- 验证输入
    if not logic.isValidSeat(seat) then
        log.error("Invalid seat: %d", seat)
        return
    end
    
    -- 验证游戏状态
    if not logic.canPlayerAct(seat) then
        log.error("Player %d cannot act in current state", seat)
        return
    end
    
    -- 处理行为
    local success, err = pcall(logic.handleAction, seat, data)
    if not success then
        log.error("Action failed: %s", err)
    end
end
```

### 性能问题

#### 1. 响应延迟高

**症状**：
- 客户端请求响应慢
- 游戏操作延迟明显

**诊断方法**：
```lua
-- 添加性能监控
local function timeAction(actionName, func, ...)
    local startTime = skynet.now()
    local result = func(...)
    local endTime = skynet.now()
    local duration = endTime - startTime
    
    if duration > 100 then  -- 超过100ms记录
        log.warn("Slow action: %s took %dms", actionName, duration)
    end
    
    return result
end
```

**解决方案**：
```lua
-- 优化消息处理
function optimizedMessageHandler(messages)
    -- 批量处理消息
    local batchSize = 10
    for i = 1, #messages, batchSize do
        local batch = {}
        for j = i, math.min(i + batchSize - 1, #messages) do
            table.insert(batch, messages[j])
        end
        processBatch(batch)
        skynet.yield()  -- 让出CPU时间片
    end
end
```

#### 2. 并发处理能力不足

**症状**：
- 大量连接时服务响应慢
- 房间创建失败

**解决方案**：
```lua
-- 增加线程池
thread = math.min(16, os.execute("nproc"))

-- 使用协程池
local coroutinePool = {}
local maxCoroutines = 100

function getCoroutine()
    if #coroutinePool > 0 then
        return table.remove(coroutinePool)
    else
        return coroutine.create(taskHandler)
    end
end

function releaseCoroutine(co)
    if #coroutinePool < maxCoroutines then
        table.insert(coroutinePool, co)
    end
end
```

### 网络问题

#### 1. WebSocket连接失败

**症状**：
- 客户端无法建立WebSocket连接
- 连接立即断开

**诊断方法**：
```bash
# 测试WebSocket连接
wscat -c ws://localhost:8001

# 检查握手过程
tcpdump -i lo port 8001
```

**解决方案**：
```lua
-- 检查WebSocket握手
function websocket.handshake(fd, header, url)
    -- 验证请求头
    if not header["upgrade"] or header["upgrade"]:lower() ~= "websocket" then
        log.error("Invalid WebSocket upgrade header")
        return false
    end
    
    -- 验证协议版本
    if not header["sec-websocket-version"] or header["sec-websocket-version"] ~= "13" then
        log.error("Unsupported WebSocket version")
        return false
    end
    
    return true
end
```

#### 2. 协议解析错误

**症状**：
- 收到无效的协议数据
- 协议解析异常

**解决方案**：
```lua
-- 添加协议验证
function parseMessage(data)
    local success, result = pcall(function()
        -- 验证数据长度
        if #data < 4 then
            error("Message too short")
        end
        
        -- 解析协议头
        local msgType = string.unpack("<I2", data, 1)
        local msgLen = string.unpack("<I2", data, 3)
        
        -- 验证消息长度
        if #data < msgLen + 4 then
            error("Incomplete message")
        end
        
        return sproto.decode(data:sub(5, 4 + msgLen))
    end)
    
    if not success then
        log.error("Protocol parse error: %s", result)
        return nil
    end
    
    return result
end
```

## 调试技巧

### 1. 开启调试模式

```lua
-- 在配置文件中添加
debug = true
logservice = "logger"

-- 设置详细日志级别
logger = {
    level = "DEBUG",
    file = "./logs/debug.log"
}
```

### 2. 使用断点调试

```lua
-- 添加断点函数
function debugBreak(message)
    log.info("DEBUG BREAK: %s", message or "")
    -- 可以在这里添加交互式调试逻辑
    io.read()  -- 等待输入
end

-- 在关键位置插入断点
function logic.onPlayerAction(seat, data)
    debugBreak("Player action: " .. tostring(seat))
    -- 处理逻辑...
end
```

### 3. 状态转储

```lua
-- 转储房间状态
function BaseRoom:dumpState()
    local state = {
        roomInfo = self.roomInfo,
        players = self.players,
        gameState = self.logicHandler and self.logicHandler.gameState or nil
    }
    
    local filename = string.format("dumps/room_%s_%d.json", 
        self.roomInfo.roomid, os.time())
    
    local file = io.open(filename, "w")
    file:write(cjson.encode(state))
    file:close()
    
    log.info("State dumped to: %s", filename)
end
```

### 4. 性能分析

```lua
-- 性能分析器
local profiler = {}
profiler.stats = {}

function profiler.start(name)
    profiler.stats[name] = profiler.stats[name] or {count = 0, totalTime = 0}
    profiler.stats[name].startTime = skynet.now()
end

function profiler.stop(name)
    local stat = profiler.stats[name]
    if stat and stat.startTime then
        local duration = skynet.now() - stat.startTime
        stat.totalTime = stat.totalTime + duration
        stat.count = stat.count + 1
        stat.avgTime = stat.totalTime / stat.count
        stat.startTime = nil
    end
end

function profiler.report()
    for name, stat in pairs(profiler.stats) do
        log.info("Profile [%s]: count=%d, total=%dms, avg=%.2fms", 
            name, stat.count, stat.totalTime, stat.avgTime)
    end
end
```

## 预防措施

### 1. 代码质量

```lua
-- 参数验证
function validateParameters(...)
    local args = {...}
    for i, arg in ipairs(args) do
        if arg == nil then
            error(string.format("Parameter %d is nil", i))
        end
    end
end

-- 边界检查
function checkBounds(value, min, max, name)
    if value < min or value > max then
        error(string.format("%s out of bounds: %d (should be %d-%d)", 
            name or "value", value, min, max))
    end
end
```

### 2. 资源管理

```lua
-- 资源清理检查
function checkResourceLeak()
    local allocated = collectgarbage("count")
    if allocated > lastAllocated * 1.5 then
        log.warn("Possible memory leak detected: %dKB allocated", allocated)
        collectgarbage("collect")
    end
    lastAllocated = allocated
end

-- 定时资源检查
skynet.fork(function()
    while true do
        skynet.sleep(6000)  -- 每分钟检查一次
        checkResourceLeak()
    end
end)
```

### 3. 监控告警

```lua
-- 异常计数器
local errorCounter = {}

function recordError(errorType)
    errorCounter[errorType] = (errorCounter[errorType] or 0) + 1
    
    -- 达到阈值时告警
    if errorCounter[errorType] > 10 then
        log.error("High error rate for %s: %d errors", 
            errorType, errorCounter[errorType])
        -- 发送告警...
    end
end
```

## 应急处理

### 1. 服务重启

```bash
#!/bin/bash
# emergency_restart.sh

echo "$(date): Emergency restart initiated" >> emergency.log

# 备份当前状态
mkdir -p emergency_backup/$(date +%Y%m%d_%H%M%S)
cp -r logs/ emergency_backup/$(date +%Y%m%d_%H%M%S)/
cp -r config/ emergency_backup/$(date +%Y%m%d_%H%M%S)/

# 强制停止服务
pkill -9 skynet

# 清理残留资源
rm -f /tmp/skynet_*

# 重启服务
./sh/runGame.sh

echo "$(date): Emergency restart completed" >> emergency.log
```

### 2. 数据恢复

```bash
#!/bin/bash
# emergency_recovery.sh

BACKUP_DIR="/backup/emergency"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 停止服务
./sh/stopGame.sh

# 恢复配置
if [ -f "$BACKUP_DIR/config_latest.tar.gz" ]; then
    tar -xzf "$BACKUP_DIR/config_latest.tar.gz"
    echo "Config restored from backup"
fi

# 恢复Redis数据
if [ -f "$BACKUP_DIR/redis_latest.rdb" ]; then
    cp "$BACKUP_DIR/redis_latest.rdb" /var/lib/redis/dump.rdb
    systemctl restart redis
    echo "Redis data restored from backup"
fi

# 重启服务
./sh/runGame.sh

echo "$(date): Emergency recovery completed" >> recovery.log
```

### 3. 故障隔离

```lua
-- 故障隔离机制
function isolateRoom(roomid, reason)
    log.error("Isolating room %s: %s", roomid, reason)
    
    -- 阻止新玩家加入
    local room = allGames[gameid][roomid]
    if room then
        skynet.send(room, "lua", "setIsolated", true)
    end
    
    -- 通知运维
    notifyOps("Room isolated", {
        roomid = roomid,
        reason = reason,
        timestamp = os.time()
    })
end
```

通过本文档的指导，开发者和运维人员应该能够有效地诊断和解决Games服务中的常见问题，确保服务的稳定运行。