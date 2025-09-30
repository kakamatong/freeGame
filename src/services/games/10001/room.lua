--[[
    Room模块 - 游戏10001特定逻辑
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
local config = require "games.10001.config"
local logicHandler = require "games.10001.logic"
local aiHandler = require "games.10001.ai"
local PrivateRoom = require "games.privateRoom"

local Room = {}
setmetatable(Room, {__index = PrivateRoom})
Room.__index = Room

-- 房间处理器和AI处理器
local roomHandler = {}
local roomHandlerAi = {}
-- 全局room实例
local roomInstance = nil

local function addLogicData(flag, seat)
    if roomInstance then
        roomInstance.roomInfo.logicData[seat] = roomInstance.roomInfo.logicData[seat] or {}

        local logicData = roomInstance.roomInfo.logicData[seat]
        logicData[flag] = logicData[flag] or 0
        logicData[flag] = logicData[flag] + 1
    end
end

local function checkCanEnd()
    if roomInstance then
        if roomInstance.roomInfo.playedCnt >= roomInstance.roomInfo.mode.maxCnt then
            return true
        end
        for key, value in pairs(roomInstance.roomInfo.playerids) do
            local logicData = roomInstance.roomInfo.logicData[key] or {}
            local win = logicData["win"] or 0
            local lose = logicData["lose"] or 0
            if win >= roomInstance.roomInfo.mode.winCnt then
                return true
            end
        end
        return false
    end

    return true
end

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
    
    -- 初始化游戏处理器
    self.logicHandler = logicHandler
    self.aiHandler = aiHandler
    self.roomHandler = roomHandler
    self.roomHandlerAi = roomHandlerAi
    
    -- 定时器间隔
    self.dTime = 100
end

-- 初始化房间逻辑
function Room:init(data)
    log.info("game10001 Room:init %s", UTILS.tableToString(data))
    
    -- 调用父类初始化
    PrivateRoom.init(self, data)
    
    -- 区分匹配房间和私人房间配置
    if self:isMatchRoom() then
        self.roomInfo.playerNum = #self.roomInfo.playerids
        self.roomInfo.nowPlayerNum = self.roomInfo.playerNum
        self.roomInfo.roomWaitingConnectTime = config.MATCH_ROOM_WAITTING_CONNECT_TIME
        self.roomInfo.roomGameTime = config.MATCH_ROOM_GAME_TIME
        self.roomInfo.mode = {name = "1局1胜",maxCnt = 1,winCnt = 1} -- 默认一局一胜
        -- 初始化匹配房间玩家
        self:_initMatchRoomPlayers(data)
    elseif self:isPrivateRoom() then
        local modeData = config.PRIVATE_ROOM_MODE[self.roomInfo.privateRule.mode or 0]
        self.roomInfo.mode = modeData
    end
    
    -- 初始化游戏状态
    self.roomInfo.roomStatus = config.ROOM_STATUS.WAITTING_CONNECT
    
    -- 加载协议
    self:loadSproto()
    
    -- 创建定时任务
    self:startTimer()
    
    -- 记录创建日志
    local ext = {
        playerids = self.roomInfo.playerids,
        gameData = self.roomInfo.gameData
    }
    self:pushLog(config.LOG_TYPE.CREATE_ROOM, 0, cjson.encode(ext))
    
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
        local status = config.PLAYER_STATUS.LOADING
        if bRobot then
            status = config.PLAYER_STATUS.READY
            robotCnt = robotCnt + 1
        else
            self:setUserStatus(userid, self.gConfig.USER_STATUS.GAMEING, self.roomInfo.gameid, self.roomInfo.roomid, self.roomInfo.addr, self.roomInfo.shortRoomid)
        end
        self:checkUserInfo(userid, seat, status, bRobot)
    end
    
    self.roomInfo.robotCnt = robotCnt
end

-- 启动定时任务
function Room:startTimer()
    skynet.fork(function()
        while true do
            skynet.sleep(self.dTime)
            if self.logicHandler then
                self.logicHandler.update()
            end
            if self.aiHandler then
                self.aiHandler.update()
            end
            self:checkRoomTimeout()
        end
    end)
end

-- 初始化游戏逻辑
function Room:initLogic()
    local ruleData = {
        playerCnt = self.roomInfo.playerNum,
    }
    if self:isPrivateRoom() then
        ruleData.STIP_TIME_LEN = {
            [2] = 9999;
        }
        ruleData.rule = self.roomInfo.privateRule
    end
    
    self.logicHandler.init(ruleData, self.roomHandler)
    self.aiHandler.init(self.roomHandlerAi, self.roomInfo.robotCnt)
end

-- 重写开始游戏方法
function Room:startGame()
    self.roomInfo.roomStatus = config.ROOM_STATUS.START
    self.roomInfo.playedCnt = self.roomInfo.playedCnt + 1
    self.roomInfo.gameStartTime = os.time()

    -- 下发当前第几局的信息
    if self:isPrivateRoom() then
        self:sendAllPrivateInfo()
    end
    
    -- 初始化逻辑，本局游戏规则，不可再改变
    self:initLogic()
    self.logicHandler.startGame()

    for _, value in pairs(self.players) do
        self:changePlayerStatus(value.userid, config.PLAYER_STATUS.PLAYING)
    end
    
    self:pushLog(config.LOG_TYPE.GAME_START, 0, "")
    log.info("game start")
end

-- 重写重连方法
function Room:relink(userid)
    local seat = self:getPlayerSeat(userid)
    if seat and self.logicHandler then
        self.logicHandler.relink(seat)
    end
end

-- AI消息处理
function roomHandlerAi.onAiMsg(seat, name, data)
    log.info("roomHandlerAi.onAiMsg %d, %s, %s", seat, name, UTILS.tableToString(data))
    if roomInstance and roomInstance.logicHandler then
        local func = roomInstance.logicHandler[name]
        if func then
            func(seat, data)
        else
            log.error("roomHandlerAi.onAiMsg method %s not found", name)
        end
    end
end

-- room接口，提供给logic调用
function roomHandler.logicMsg(seat, name, data)
    if roomInstance then
        if 0 == seat then
            roomInstance:sendToAllClient(name, data)
        else
            local userid = roomInstance.roomInfo.playerids[seat]
            roomInstance:sendToOneClient(userid, name, data)
        end
    end
end

-- room接口，游戏结果
function roomHandler.gameResult(data)
    if not roomInstance then
        return
    end
    
    local day = os.date("%Y%m%d")
    local rankKey = "game10001DayRank:" .. day
    local scores = {}
    for k, v in pairs(data) do
        local userid = roomInstance.roomInfo.playerids[v.seat]
        local flag = config.RESULT_TYPE.NONE
        local addType = "other"
        local score = 0

        -- 需要记录各个座位赢的次数和输的次数
        if v.endResult == 1 then
            flag = config.RESULT_TYPE.WIN
            addType = "win"
            score = 4
        elseif v.endResult == 2 then
            flag = config.RESULT_TYPE.DRAW
            addType = "draw"
            score = 1
        else 
            flag = config.RESULT_TYPE.LOSE
            addType = "lose"
        end

        addLogicData(addType,v.seat)

        scores[v.seat] = score
        
        local totalScore = skynet.call(roomInstance.svrDB, "lua", "dbRedis", "zscore", rankKey, userid) or 0
        totalScore = totalScore + score
        skynet.call(roomInstance.svrDB, "lua", "dbRedis", "zadd", rankKey, totalScore, userid)
        skynet.call(roomInstance.svrDB, "lua", "dbRedis", "expire", rankKey, 86400 * 7)

        local tmp = {
            playerids = roomInstance.roomInfo.playerids,
            data = data,
        }
        roomInstance:pushLogResult(config.LOG_RESULT_TYPE.GAME_END, userid, flag, 0, 0, 0, 0, 0, cjson.encode(tmp))
        roomInstance:pushUserGameRecords(userid, addType, 1)
    end

    return scores
end

-- room接口，游戏结束
function roomHandler.gameEnd()
    if roomInstance then
        if checkCanEnd() then
            roomInstance:roomEnd(config.ROOM_END_FLAG.GAME_END)
        else
            roomInstance:changeAllPlayerStatus(config.PLAYER_STATUS.ONLINE)
        end
    end
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

-- 出牌操作
function REQUEST:outHand(userid, args)
    if roomInstance then
        local seat = roomInstance:getPlayerSeat(userid)
        if seat and roomInstance.logicHandler then
            roomInstance.logicHandler.outHand(seat, args)
        end
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
        log.info("room dispatch fd %d, type %s", fd, type)
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
