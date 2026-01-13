--[[
WebSocket游戏网关服务
负责处理游戏客户端的WebSocket连接、认证、房间分配和消息转发
]]
local skynet = require "skynet"
local wsGateserver = require "wsGateserver"  -- WebSocket网关服务器模块
local websocket = require "http.websocket"   -- WebSocket处理模块
local urlTools = require "http.url"          -- URL工具模块
local log = require "log"                    -- 日志模块

local connection = {}  -- 连接池: { fd -> connection : { fd , client, agent , ip, mode } }
local logins = {}      -- 登录池: { uid -> fd }

-- 注册客户端协议
skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
}

--[[
取消消息转发
@param c 连接对象
]]
local function unforward(c)
    if c.agent then
        c.agent = nil
        c.client = nil
    end
end

--[[
清除登录记录
@param c 连接对象
]]
local function clearLogin(c)
    if c.userid then
        logins[c.userid] = nil
    end
end

--[[
关闭文件描述符
@param fd socket连接句柄
]]
local function close_fd(fd)
    local c = connection[fd]
    if c then
        if c.room then
            skynet.send(c.room, "lua", "socketClose", fd)
        end
        clearLogin(c)
        unforward(c)
        connection[fd] = nil
    end
end

--[[
根据用户ID踢下线
@param userid 用户ID
]]
local function kickByUserid(userid)
    local fd = logins[userid]
    if fd then
        wsGateserver.closeclient(fd)
    end
end

--[[
获取游戏房间服务
@param gameid 游戏ID
@param roomid 房间ID
@return 房间服务地址或false
]]
local function getRoom(gameid, roomid)
    local svrGameManager = skynet.localname(CONFIG.SVR_NAME.GAMES)
    if not svrGameManager then
        return false
    end

    local res = skynet.call(svrGameManager, "lua", "getGame", gameid, roomid)
    return res
end

--[[
认证函数
@param data 认证数据
@return 认证结果
]]
local function auth(data)
    return call(CONFIG.CLUSTER_SVR_NAME.AUTH, "authGame", data)
end

--[[
连接游戏房间
@param data 连接数据，包含gameid, roomid, userid, client_fd等
@return 连接结果
]]
local function connectGame(data)
    local svrGameManager = skynet.localname(CONFIG.SVR_NAME.GAMES)
    if not svrGameManager then
        return false
    end

    local gameid = tonumber(data.gameid)
    local roomid = tonumber(data.roomid)
    local userid = tonumber(data.userid)
    local client_fd = tonumber(data.client_fd)

    return skynet.call(svrGameManager, "lua", "connectGame", userid, gameid, roomid, client_fd)
end

--[[
启动心跳检测
定期检查连接活跃度，超过15秒无响应则关闭连接
]]
local function startCheckAlive()
    skynet.fork(function ()
        while true do
            skynet.sleep(1000) -- 10秒检查一次
            local now = skynet.time()
            for fd, c in pairs(connection) do
                if now - c.lastTime > 15 then
                    log.info("wsGameGate checkAlive: close inactive connection")
                    websocket.close(fd)
                else
                    websocket.ping(fd) -- 发送ping包
                end
            end
        end
    end)
end

-- 网关处理器
local handler = {}

--[[
网关打开回调
@param source 来源
@param conf 配置
@return 地址和端口
]]
function handler.open(source, conf)
    log.info("wsGameGate open")

    startCheckAlive() -- 启动心跳检测
    return conf.address, conf.port
end

--[[
消息处理回调
@param fd socket连接句柄
@param msg 消息内容
@param msgType 消息类型
]]
function handler.message(fd, msg, msgType)
    --log.info("wsGameGate message")
    -- 接收到消息，转发给对应的房间服务
    local c = connection[fd]
    if c and c.room then
        skynet.redirect(c.room, fd, "client", fd, msg, string.len(msg))
    else
        skynet.trash(msg,string.len(msg)) -- 回收未使用的消息
    end
end

--[[
连接回调
@param fd socket连接句柄
]]
function handler.connect(fd)
    log.info("wsGameGate connect: fd=%d", fd)
end

--[[
认证回调
@param fd socket连接句柄
@param uri 请求URI
@param addr 客户端地址
@return 认证结果和用户ID
]]
function handler.auth(fd, header, url)
    log.info("wsgate auth %d, %s", fd, url)
    local data = urlTools.parse_query(url)
    data.ip = header["x-real-ip"] or "0.0.0.0"
    data.uri = url
    data.client_fd = fd
    local userid = tonumber(data.userid)
    -- 先连接游戏房间，再认证玩家
    return connectGame(data) and auth(data), userid
end

--[[
握手回调
@param fd socket连接句柄
@param header 头信息
@param uri 请求URI
]]
function handler.handshake(fd, header, url)
    local data = urlTools.parse_query(url)
	local userid = tonumber(data.userid) or 0
    local room = getRoom(tonumber(data.gameid), tonumber(data.roomid))
    local c = {
        fd = fd,
        userid = userid,
        addr = url,
        room = room,
        lastTime = skynet.time()  -- 记录最后活动时间
    }

    kickByUserid(userid) -- 踢掉已登录的同用户
    logins[userid] = fd
    connection[fd] = c
end

--[[
关闭回调
@param fd socket连接句柄
]]
function handler.close(fd)
    log.info("wsGameGate close: fd=%d", fd)
    close_fd(fd)
end

--[[
错误回调
@param fd socket连接句柄
@param msg 错误消息
]]
function handler.error(fd, msg)
    log.info("wsGameGate error: fd=%d, msg=%s", fd, msg)
    close_fd(fd)
end

--[[
Ping回调
@param fd socket连接句柄
]]
function handler.ping(fd)
    --log.info("wsGameGate ping: fd=%d", fd)
    connection[fd].lastTime = skynet.time() -- 更新最后活动时间
end

--[[
Pong回调
@param fd socket连接句柄
]]
function handler.pong(fd)
    --log.info("wsGameGate pong: fd=%d", fd)
    connection[fd].lastTime = skynet.time() -- 更新最后活动时间
end

-- 命令表
local CMD = {}

--[[
发送消息
@param source 来源
@param fd socket连接句柄
@param msg 消息内容
]]
function CMD.send(source, fd, msg)
    if not connection[fd] then
        log.warn("wsgate send error: fd not found %d", fd)
        return
    end
    websocket.write(fd, msg, "binary")
end

--[[
房间结束
@param source 来源
@param fd socket连接句柄
]]
function CMD.roomOver(source, fd)
    websocket.close(fd)
end

--[[
命令处理
@param cmd 命令
@param source 来源
@param ... 参数
@return 处理结果
]]
function handler.command(cmd, source, ...)
    local f = assert(CMD[cmd])
    return f(source, ...)
end

-- 启动WebSocket游戏网关服务
wsGateserver.start(handler, CONFIG.SVR_NAME.GAME_GATE)
