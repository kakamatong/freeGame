--[[
    Room模块 - 游戏10002特定逻辑
    继承：PrivateRoom -> BaseRoom
    功能：
    1. 游戏逻辑处理
    2. AI交互管理
    3. 游戏结果统计
    4. 游戏特定配置
]]

local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local config = require "games.10002.config"
local PrivateRoom = require "games.privateRoom"

local Room = {}
setmetatable(Room, {__index = PrivateRoom})
Room.__index = Room

-- 全局room实例
local roomInstance = nil

-- 构造函数
function Room:new()
    local obj = PrivateRoom:new()
    setmetatable(obj, self)
    obj:_initRoom()
    return obj
end

-- 游戏特定初始化
function Room:_initRoom()
    -- 设置游戏配置
    self.config = config
    
    -- 定时器间隔
    self.dTime = 100
end

-- 初始化房间逻辑
function Room:init(data)
    log.info("game10002 Room:init %s", UTILS.tableToString(data))
    
    -- 调用父类初始化
    PrivateRoom.init(self, data)
    
    -- 区分匹配房间和私人房间配置
    if self:isMatchRoom() then
        self.roomInfo.playerNum = #self.roomInfo.playerids
        self.roomInfo.nowPlayerNum = self.roomInfo.playerNum
        self.roomInfo.roomWaitingConnectTime = config.MATCH_ROOM_WAITTING_CONNECT_TIME or 30
        self.roomInfo.roomGameTime = config.MATCH_ROOM_GAME_TIME or 600
        -- 初始化匹配房间玩家
        self:_initMatchRoomPlayers(data)
    elseif self:isPrivateRoom() then
        local modeData = config.PRIVATE_ROOM_MODE and config.PRIVATE_ROOM_MODE[self.roomInfo.privateRule.mode or 0] or {name = "默认模式", maxCnt = 1, winCnt = 1}
        self.roomInfo.mode = modeData
    end
    
    -- 初始化游戏状态
    self.roomInfo.roomStatus = config.ROOM_STATUS and config.ROOM_STATUS.WAITTING_CONNECT or 1
    
    -- 加载协议
    self:loadSproto()
    
    -- 创建定时任务
    self:startTimer()
    
    -- 记录创建日志
    local ext = {
        playerids = self.roomInfo.playerids,
        gameData = self.roomInfo.gameData
    }
    self:pushLog(config.LOG_TYPE and config.LOG_TYPE.CREATE_ROOM or 1, 0, cjson.encode(ext))
    
    -- 检查是否可以开始游戏
    self:testStart()
end

-- 初始化匹配房间玩家
function Room:_initMatchRoomPlayers(data)
    local robotCnt = 0
    local isRobotFunc = function (userid)
        if data.gameData.robots and #data.gameData.robots > 0 and userid and userid > 0 then
            for _, id in pairs(data.gameData.robots) do
                if id == userid then
                    return true
                end
            end
        end
        return false
    end
    
    for seat, userid in pairs(self.roomInfo.playerids) do
        local bRobot = isRobotFunc(userid)
        local status = config.PLAYER_STATUS and config.PLAYER_STATUS.LOADING or 1
        if bRobot then
            status = config.PLAYER_STATUS and config.PLAYER_STATUS.READY or 2
            robotCnt = robotCnt + 1
        else
            self:setUserStatus(userid, self.gConfig.USER_STATUS.GAMEING, self.roomInfo.gameid, self.roomInfo.roomid, self.roomInfo.addr, self.roomInfo.shortRoomid)
        end
        -- 匹配场的战力是匹配的时候传过来的
        self:checkUserInfo(userid, seat, status, bRobot, data.gameData.rate and data.gameData.rate[seat] or 0)
    end
    
    self.roomInfo.robotCnt = robotCnt
end

-- 启动定时任务
function Room:startTimer()
    skynet.fork(function()
        while true do
            skynet.sleep(self.dTime)
            self:checkRoomTimeout()
        end
    end)
end

-- 重写开始游戏方法
function Room:startGame()
    self.roomInfo.roomStatus = config.ROOM_STATUS and config.ROOM_STATUS.START or 2
    self.roomInfo.playedCnt = self.roomInfo.playedCnt + 1
    self.roomInfo.gameStartTime = os.time()

    -- 下发当前第几局的信息
    if self:isPrivateRoom() then
        self.roomInfo.record[self.roomInfo.playedCnt] = self.roomInfo.record[self.roomInfo.playedCnt] or {}
        self.roomInfo.record[self.roomInfo.playedCnt].index = self.roomInfo.playedCnt -- 第几局
        self.roomInfo.record[self.roomInfo.playedCnt].startTime = os.time()
        self:sendAllPrivateInfo()
    end
    
    for _, value in pairs(self.players) do
        self:changePlayerStatus(value.userid, config.PLAYER_STATUS and config.PLAYER_STATUS.PLAYING or 3)
    end
    
    self:pushLog(config.LOG_TYPE and config.LOG_TYPE.GAME_START or 2, 0, "")
    log.info("game10002 game start")
end

-- 重写重连方法
function Room:relink(userid)
    log.info("game10002 Room:relink %d", userid)
    -- TODO: 实现游戏特定的重连逻辑
end

-- 命令接口
local CMD = {}

-- 初始化房间逻辑
function CMD.start(data)
    roomInstance = Room:new()
    roomInstance:init(data)
end

-- 连接游戏
function CMD.connectGame(userid, client_fd)
    if roomInstance then
        return roomInstance:connectGame(userid, client_fd)
    end
    return false
end

-- 加入私人房
function CMD.joinPrivateRoom(userid)
    if roomInstance then
        return roomInstance:joinPrivateRoom(userid)
    end
    return false, "房间未初始化"
end

-- 停止房间
function CMD.stop()
    if roomInstance then
        roomInstance:stop()
    end
end

-- 处理socket关闭
function CMD.socketClose(fd)
    if roomInstance then
        roomInstance:socketClose(fd)
    end
end

-- 客户端请求接口
local REQUEST = {}

-- 客户端准备
function REQUEST:clientReady(userid, args)
    if roomInstance then
        roomInstance:clientReady(userid, args)
    end
end

-- 游戏准备
function REQUEST:gameReady(userid, args)
    if roomInstance then
        return roomInstance:gameReady(userid, args.ready)
    end
    return {code = 0, msg = "房间未初始化"}
end

-- 离开房间
function REQUEST:leaveRoom(userid, args)
    if roomInstance then
        return roomInstance:leaveRoom(userid)
    end
    return {code = 0, msg = "房间未初始化"}
end

-- 发起投票解散
function REQUEST:voteDisbandRoom(userid, args)
    if roomInstance then
        return roomInstance:voteDisbandRoom(userid, args.reason)
    end
    return {code = 0, msg = "房间未初始化"}
end

-- 投票解散响应
function REQUEST:voteDisbandResponse(userid, args)
    if roomInstance then
        return roomInstance:voteDisbandResponse(userid, args.voteId, args.agree)
    end
    return {code = 0, msg = "房间未初始化"}
end

-- 客户端请求分发
local function request(fd, name, args, response)
    if not roomInstance then
        log.error("request error: roomInstance not initialized")
        return
    end
    
    local userid = roomInstance:getUseridByFd(fd)
    if not userid then
        log.error("request fd %d not found userid", fd)
        return
    end
    
    local func = REQUEST[name]
    if not func then
        log.error("request method %s not found", name)
        return
    end
    
    local res = func(REQUEST, userid, args)
    if response and res then
        return response(res)
    end
end

-- 注册客户端协议，处理客户端消息
skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
    unpack = function (msg, sz)
        local str = skynet.tostring(msg, sz)
        if roomInstance and roomInstance.host then
            return roomInstance.host:dispatch(str, sz)
        end
        return nil
    end,
    dispatch = function (fd, _, type, ...)
        log.info("room10002 dispatch fd %d, type %s", fd, type)
        skynet.ignoreret() -- session是fd，不需要返回
        if type == "REQUEST" then
            local ok, result = pcall(request, fd, ...)
            if ok then
                if result and roomInstance then
                    roomInstance:send_package(fd, result)
                end
            else
                log.error(result)
            end
        else
            assert(type == "RESPONSE")
            error "This example doesn't support request client"
        end
    end
}

-- 服务启动
skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        end
    end)
end)
