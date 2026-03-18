--[[
    Room模块 - 游戏10002（连连看）房间逻辑
    继承：PrivateRoom -> BaseRoom
    职责：房间管理、玩家连接、生命周期管理
    游戏逻辑通过 logicHandler 委托给 logic.lua
]]

local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local config = require "games.10002.config"
local PrivateRoom = require "games.privateRoom"
local logicHandler = require "games.10002.logic"
local aiHandler = require "games.10002.ai"
local ScoringSystem = require "games.10002.scoring"

local Room = {}
setmetatable(Room, {__index = PrivateRoom})
Room.__index = Room

-- 全局room实例
local roomInstance = nil

-- Room -> Logic 的通信接口
local roomHandler = {}

-- 获取房间最大局数
function roomHandler.getMaxRound()
    if not roomInstance then return 1 end
    return roomInstance.roomInfo.mode and roomInstance.roomInfo.mode.maxCnt or 1
end

-- Room -> AI 的通信接口
local roomHandlerAi = {}

--[[
    发送消息给指定座位
    @param seat: number 座位号
    @param name: string 消息名
    @param data: table 消息数据
]]
function roomHandler.sendToSeat(seat, name, data)
    if not roomInstance then return end
    
    -- 检查是否是机器人，如果是则发送给AI处理
    if roomInstance:isRobotBySeat(seat) then
        if aiHandler.onMsg then
            aiHandler.onMsg(seat, name, data)
        end
        return
    end
    
    local userid = roomInstance.roomInfo.playerids[seat]
    if userid then
        roomInstance:sendToOneClient(userid, name, data)
    end
end

--[[
    广播消息给所有玩家
    @param name: string 消息名
    @param data: table 消息数据
]]
function roomHandler.sendToAll(name, data)
    if not roomInstance then return end
    
    -- 发送给机器人（所有座位都要检查）
    for seat = 1, roomInstance.roomInfo.playerNum do
        if roomInstance:isRobotBySeat(seat) then
            if aiHandler.onMsg then
                aiHandler.onMsg(seat, name, data)
            end
        end
    end
    
    roomInstance:sendToAllClient(name, data)
end

--[[
    玩家完成游戏回调
    @param seat: number 座位号
    @param usedTime: number 用时（秒）
    @param rank: number 排名
]]
function roomHandler.onPlayerFinish(seat, usedTime, rank)
    if not roomInstance then return end
    log.info("[Room] 玩家座位%d完成游戏，用时: %d秒，排名: %d", seat, usedTime, rank)
    -- 可以在这里记录日志、更新统计数据等
end

--[[
    单局游戏结束回调
    @param endType: number 结束类型
    @param rankings: table 排名列表
]]
function roomHandler.onGameEnd(endType, rankings)
    if not roomInstance then return end
    log.info("[Room] 第%d局结束，类型: %d", roomInstance.roomInfo.playedCnt, endType)
    
    local currentRound = roomInstance.roomInfo.playedCnt
    
    local roundScores = {}
    if roomInstance:isMatchRoom() then
        local day = os.date("%Y%m%d")
        local rankKey = "game10002:day:" .. day
        local playerScores = {}
        
        for seat, userid in ipairs(roomInstance.roomInfo.playerids) do
            local score = skynet.call(roomInstance.svrDB, "lua", "dbRedis", "zscore", rankKey, userid) or 0
            playerScores[seat] = score
        end
        
        local scoreResults = roomInstance.scoringMatch:calculateMatchScore(playerScores, rankings)
        
        for seat, userid in ipairs(roomInstance.roomInfo.playerids) do
            local result = scoreResults[seat]
            if result then
                local newScore = result.newScore
                skynet.call(roomInstance.svrDB, "lua", "dbRedis", "zadd", rankKey, newScore, userid)
                skynet.call(roomInstance.svrDB, "lua", "dbRedis", "expire", rankKey, 86400 * 7)
                
                roundScores[seat] = {
                    oldScore = result.oldScore,
                    newScore = result.newScore,
                    delta = result.delta,
                    rank = result.rank or 0,
                }
                
                log.info("[Room] 匹配模式计分: 座位%d 用户%d 分数%d->%d (delta:%d)",
                    seat, userid, result.oldScore, result.newScore, result.delta)
            end
        end
        
        roomInstance.roomInfo.record[currentRound] = roomInstance.roomInfo.record[currentRound] or {}
        roomInstance.roomInfo.record[currentRound].scores = roundScores
    elseif roomInstance:isPrivateRoom() then
        local playerCnt = roomInstance.roomInfo.nowPlayerNum
        local scoreResults = roomInstance.scoringMatch:calculatePrivateScore(playerCnt, rankings)
        
        for seat, result in pairs(scoreResults) do
            roundScores[seat] = {
                score = result.score,
                rank = result.rank,
            }
            log.info("[Room] 私人房计分: 座位%d 得分%d 排名%d",
                seat, result.score, result.rank)
        end
        
        roomInstance.roomInfo.record[currentRound] = roomInstance.roomInfo.record[currentRound] or {}
        roomInstance.roomInfo.record[currentRound].scores = roundScores
    end
    
    if roomInstance.roomInfo.record then
        roomInstance.roomInfo.record[currentRound] = roomInstance.roomInfo.record[currentRound] or {}
        roomInstance.roomInfo.record[currentRound].endTime = os.time()
        roomInstance.roomInfo.record[currentRound].rankings = rankings
    end
    
    if roomInstance:isPrivateRoom() then
        local mode = roomInstance.roomInfo.mode
        if mode and currentRound < mode.maxCnt then
            log.info("[Room] 第%d/%d局结束，等待玩家准备下一局", currentRound, mode.maxCnt)
            roomInstance.roomInfo.roomStatus = config.ROOM_STATUS.HALFTIME
            
            for _, player in pairs(roomInstance.players) do
                roomInstance:changePlayerStatus(player.userid, config.PLAYER_STATUS.ONLINE)
            end
            return
        end
    end
    
    log.info("[Room] 所有局结束，房间关闭")
    roomInstance:roomEnd(config.ROOM_END_FLAG.GAME_END)
end

--[[
    获取游戏时间
    @return number 当前游戏时间（秒）
]]
function roomHandler.getGameTime()
    if not roomInstance then return 0 end
    return os.time() - roomInstance.roomInfo.gameStartTime
end

--[[
    ==================== RoomHandlerAi 接口（供AI调用） ====================
]]

--[[
    AI发送消息给Logic
    @param seat: number 座位号
    @param name: string 消息名
    @param data: table 消息数据
]]
function roomHandlerAi.onAiMsg(seat, name, data)
    log.info("[RoomHandlerAi] 座位%d AI消息: %s", seat, name)
    if roomInstance and roomInstance.logicHandler then
        local func = roomInstance.logicHandler[name]
        if func then
            local result = func(seat, data)
            log.info("[RoomHandlerAi] 座位%d AI消息处理结果: %s", seat, UTILS.tableToString(result or {}))
        else
            log.error("[RoomHandlerAi] 未找到处理方法: %s", name)
        end
    end
end

--[[
    获取指定座位的可消除方块对（供AI决策使用）
    @param seat: number 座位号
    @return table 可消除的方块对数组
]]
function roomHandlerAi.getValidPairs(seat)
    if not roomInstance then return {} end
    
    -- 从logicHandler获取玩家地图
    if roomInstance.logicHandler and roomInstance.logicHandler.getPlayerMap then
        local playerMap = roomInstance.logicHandler.getPlayerMap(seat)
        if playerMap and playerMap.getAllValidPairs then
            local pairs = playerMap:getAllValidPairs()
            log.debug("[RoomHandlerAi] 座位%d可消除方块对数量: %d", seat, #pairs)
            return pairs
        end
    end
    
    return {}
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
    
    -- 游戏逻辑处理器引用
    self.logicHandler = logicHandler
    
    -- AI处理器引用
    self.aiHandler = aiHandler
    self.roomHandlerAi = roomHandlerAi
    
    -- 计分系统
    self.scoringMatch = ScoringSystem.new(config.SCORING.MATCH)
    
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
        -- 动态获取人数，基于实际加入的玩家
        local playNum = self.roomInfo.privateRule.playNum or 1
        -- 设置房间最大人数（dispatchSeat需要用到）
        self.roomInfo.playerNum = config.PRIVATE_ROOM.MAX_PLAYERS
        self.roomInfo.nowPlayerNum = #self.roomInfo.playerids
        self.roomInfo.mode = {
            maxCnt = playNum,
            playerCnt = self.roomInfo.nowPlayerNum
        }
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
            -- 为机器人注册AI
            if self.aiHandler and self.aiHandler.addRobot then
                self.aiHandler.addRobot(seat)
            end
        else
            self:setUserStatus(userid, self.gConfig.USER_STATUS.GAMEING, self.roomInfo.gameid, self.roomInfo.roomid, self.roomInfo.addr, self.roomInfo.shortRoomid)
        end
        -- 匹配场的战力是匹配的时候传过来的
        self:checkUserInfo(userid, seat, status, bRobot, data.gameData.rate and data.gameData.rate[seat] or 0)
    end
    
    self.roomInfo.robotCnt = robotCnt
end

-- 初始化游戏逻辑
function Room:initLogic()
    local ruleData = {
        playerCnt = self.roomInfo.nowPlayerNum,
        mapRows = config.MAP.DEFAULT_ROWS,
        mapCols = config.MAP.DEFAULT_COLS,
        iconTypes = config.MAP.ICON_TYPES,
    }
    
    self.logicHandler.init(ruleData, roomHandler)
    self.aiHandler.init(roomHandlerAi, self.roomInfo.robotCnt)
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

-- 重写testStart方法（支持房主直接开始或所有玩家准备后开始）
function Room:testStart()
    log.info("Room10002:testStart")
    
    -- 非私人房沿用旧逻辑：所有玩家都准备才能开始
    if not self:isPrivateRoom() then
        local readyCount = self:getReadyCnt()
        if readyCount == self.roomInfo.playerNum then
            self:startGame()
            return true
        end
        return false
    end
    
    -- 私人房逻辑：房主可直接开始，或所有普通玩家都准备
    local readyCount = self:getReadyCnt()
    local playerNum = self.roomInfo.nowPlayerNum
    
    -- 所有玩家都准备（包括房主）才能开始
    if readyCount == playerNum then
        self:startGame()
        return true
    end
    
    return false
end

-- 重写开始游戏方法
function Room:startGame()
    self.roomInfo.roomStatus = config.ROOM_STATUS.START
    self.roomInfo.playedCnt = self.roomInfo.playedCnt + 1
    self.roomInfo.gameStartTime = os.time()
    
    -- 初始化逻辑
    self:initLogic()
    
    -- 开始游戏逻辑，传入局数
    self.logicHandler.startGame(self.roomInfo.playedCnt)
    
    -- 更新玩家状态
    for _, value in pairs(self.players) do
        self:changePlayerStatus(value.userid, config.PLAYER_STATUS.PLAYING)
    end
    
    -- 下发当前第几局的信息
    if self:isPrivateRoom() then
        self.roomInfo.record[self.roomInfo.playedCnt] = self.roomInfo.record[self.roomInfo.playedCnt] or {}
        self.roomInfo.record[self.roomInfo.playedCnt].index = self.roomInfo.playedCnt
        self.roomInfo.record[self.roomInfo.playedCnt].startTime = os.time()
        self:sendAllPrivateInfo()
    end
    
    self:pushLog(config.LOG_TYPE.GAME_START, 0, "")
    log.info("game10002 game start, player count: %d", self.roomInfo.playerNum)
end

-- 重写重连方法
function Room:relink(userid)
    log.info("game10002 Room:relink %d", userid)
    local seat = self:getPlayerSeat(userid)
    if not seat then
        return
    end
    
    -- 转发给逻辑模块处理
    if self.logicHandler then
        self.logicHandler.relink(seat)
    end
end

-- 重写发送总成绩方法（按排名积分）
function Room:sendTotalResult()
    if not self.roomInfo.record then
        return
    end

    local playerCnt = self.roomInfo.mode and self.roomInfo.mode.playerCnt or self.roomInfo.playerNum
    local userInfo = {}
    
    -- 为每个座位初始化数据
    for seat, userid in ipairs(self.roomInfo.playerids) do
        userInfo[seat] = {
            userid = userid,
            seat = seat,
            totalScore = 0,
            roundDetails = {}
        }
    end
    
    -- 遍历每局记录，计算积分
    for roundNum, roundData in pairs(self.roomInfo.record) do
        if roundData and roundData.rankings then
            for _, rankInfo in ipairs(roundData.rankings) do
                local seat = rankInfo.seat
                if userInfo[seat] then
                    local rank = rankInfo.rank or 0
                    local finished = rank > 0
                    -- 积分计算：完成的玩家得 (playerCnt - rank + 1) 分，未完成得0分
                    local score = finished and (playerCnt - rank + 1) or 0
                    
                    userInfo[seat].roundDetails[roundNum] = {
                        rank = rank,
                        score = score,
                        finished = finished,
                        usedTime = rankInfo.usedTime or -1,
                        eliminated = rankInfo.eliminated or 0
                    }
                    userInfo[seat].totalScore = userInfo[seat].totalScore + score
                end
            end
        end
    end
    
    -- 转换为数组格式
    local totalResultInfo = {}
    for _, info in pairs(userInfo) do
        table.insert(totalResultInfo, info)
    end
    
    -- 按总积分排序（高分在前）
    table.sort(totalResultInfo, function(a, b)
        return a.totalScore > b.totalScore
    end)

    local data = {
        startTime = self.roomInfo.createRoomTime,
        endTime = os.time(),
        shortRoomid = self.roomInfo.shortRoomid,
        roomid = self.roomInfo.roomid,
        owner = self.roomInfo.owner,
        rule = self.roomInfo.gameData.rule or "{}",
        playCnt = self.roomInfo.playedCnt,
        maxCnt = self.roomInfo.mode.maxCnt,
        playerCnt = playerCnt,
        totalResultInfo = totalResultInfo
    }
    self:sendToAllClient("totalResult", data)
end

-- 房间转发协议
function Room:forwardMessage(userid, args)
    local msgType = args.type
    local toUserid = args.to
    local msg = args.msg
    local from = userid
    log.info("Room:forwardMessage %d %s", userid, UTILS.tableToString(args))

    local data = {
        type = msgType,
        from = from,
        msg = msg
    }
    if not toUserid or #toUserid == 0 then
        self:sendToAllClient("forwardMessage", data)
    else
        for _, value in pairs(toUserid) do
            if self.players[value] then
                self:sendToOneClient(value, "forwardMessage", data)
            end
        end
    end

    return {code = 1, msg = "success"}
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

-- 重写joinPrivateRoom方法（支持动态人数，最多6人）
function Room:joinPrivateRoom(userid)
    if self.roomInfo.roomStatus == self.config.ROOM_STATUS.START or 
       self.roomInfo.roomStatus == self.config.ROOM_STATUS.END then
        return false, "游戏已开始"
    end

    -- 动态人数上限：最多6人（从配置读取）
    local maxPlayers = config.PRIVATE_ROOM.MAX_PLAYERS
    if self.roomInfo.nowPlayerNum < maxPlayers then
        -- 检查玩家是否已在房间
        local alreadyIn = false
        for key, value in pairs(self.roomInfo.playerids) do
            if value == userid then
                alreadyIn = true
                break
            end
        end

        if not alreadyIn then
            local seat = self:dispatchSeat()
            if seat then
                self.roomInfo.playerids[seat] = userid
                self.roomInfo.nowPlayerNum = self.roomInfo.nowPlayerNum + 1
                -- 更新mode中的实际玩家数
                if self.roomInfo.mode then
                    self.roomInfo.mode.playerCnt = self.roomInfo.nowPlayerNum
                end
                self:setUserStatus(userid, self.gConfig.USER_STATUS.GAMEING, self.roomInfo.gameid, self.roomInfo.roomid, self.roomInfo.addr, self.roomInfo.shortRoomid)
                -- 私人房战力拉去
                local rices = skynet.call(self.svrDB, "lua", "db", "getUserRichesByType", userid, CONFIG.RICH_TYPE.COMBAT_POWER)
                local cp = 0
                if rices then
                    cp = rices.richNums
                end
                self:checkUserInfo(userid, seat, self.config.PLAYER_STATUS.LOADING, false, cp)
                self:onPlayerJoin(userid)
                return true
            else
                return false, "分配座位错误"
            end
        else
            return true -- 已在房间，直接返回成功
        end
    else 
        return false, "人已满"
    end
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

-- 房主开始游戏（仅房主可用）
function REQUEST:ownerStartGame(userid, args)
    if not roomInstance then
        return {code = 0, msg = "房间未初始化"}
    end
    
    -- 检查是否是私人房
    if not roomInstance:isPrivateRoom() then
        return {code = 0, msg = "非私人房间"}
    end
    
    -- 检查是否是房主
    if not roomInstance:isOwner(userid) then
        return {code = 0, msg = "只有房主可以开始游戏"}
    end
    
    -- 检查房间状态
    if roomInstance.roomInfo.roomStatus ~= config.ROOM_STATUS.WAITTING_CONNECT then
        return {code = 0, msg = "游戏已开始或已结束"}
    end
    
    -- 检查人数（至少2人才能开始）
    if roomInstance.roomInfo.nowPlayerNum < 2 then
        return {code = 0, msg = "人数不足，需要至少2人才能开始"}
    end
    
    -- 检查是否有玩家未准备
    local notReadyUserids = {}
    for seat, pid in ipairs(roomInstance.roomInfo.playerids) do
        local player = roomInstance.players[pid]
        if player and player.status ~= config.PLAYER_STATUS.READY then
            -- 房主不需要检查
            if not roomInstance:isOwner(pid) then
                table.insert(notReadyUserids, pid)
            end
        end
    end
    
    if #notReadyUserids > 0 then
        return {code = 0, msg = "有玩家未准备", notReadyUserids = notReadyUserids}
    end
    
    -- 开始游戏
    roomInstance:startGame()
    return {code = 1, msg = "游戏开始"}
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

-- 处理点击消除请求
function REQUEST:clickTiles(userid, args)
    if not roomInstance then
        return {code = 0, msg = "房间未初始化"}
    end
    
    local seat = roomInstance:getPlayerSeat(userid)
    if not seat then
        return {code = 0, msg = "玩家不在房间中"}
    end
    
    -- 转发给逻辑模块处理
    if roomInstance.logicHandler then
        return roomInstance.logicHandler.clickTiles(seat, args)
    end
    
    return {code = 0, msg = "逻辑模块未初始化"}
end

-- 消息转发
function REQUEST:forwardMessage(userid, args)
    if roomInstance then
        return roomInstance:forwardMessage(userid, args)
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
        skynet.ignoreret()
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
