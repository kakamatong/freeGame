--[[
    PrivateRoom模块 - 私人房特有功能
    继承：BaseRoom
    功能：
    1. 私人房间创建和配置
    2. 房主权限管理  
    3. 玩家加入/离开逻辑
    4. 座位分配管理
    5. 游戏准备逻辑
]]

local skynet = require "skynet"
local BaseRoom = require "games.baseRoom"
local log = require "log"
local cjson = require "cjson"
local configPrivateRoom = require "games.configPrivateRoom"
local PrivateRoom = {}
setmetatable(PrivateRoom, {__index = BaseRoom})
PrivateRoom.__index = PrivateRoom

-- 构造函数
function PrivateRoom:new()
    local obj = BaseRoom:new()
    setmetatable(obj, self)
    obj:_initPrivateRoom()
    return obj
end

-- 私人房特有初始化
function PrivateRoom:_initPrivateRoom()
    -- 私人房扩展信息
    self.roomInfo.owner = 0          -- 房主ID
    self.roomInfo.shortRoomid = 0    -- 短房间ID
    self.roomInfo.privateRule = nil  -- 私人房间规则
    
    -- 投票解散相关状态
    self.voteDisbandInfo = {
        inProgress = false,          -- 是否正在投票
        stopTimer = false,            -- 是否停止倒计时
        voteId = 0,                  -- 投票ID
        initiator = 0,               -- 发起人
        reason = "",                 -- 解散原因
        startTime = 0,               -- 开始时间
        timeLimit = 120,             -- 时间限制(秒)
        votes = {},                  -- 投票记录 {userid = vote} vote: 1=同意, 0=拒绝, nil=未投票
        needAgreeCount = 0,          -- 需要同意的人数
        timer = nil                  -- 定时器
    }
end

-- 初始化私人房数据
function PrivateRoom:init(data)
    -- 调用父类初始化
    BaseRoom.init(self, data)
    
    -- 私人房特有配置
    if self:isPrivateRoom() then
        self.roomInfo.shortRoomid = data.shortRoomid or 0
        self.roomInfo.privateRule = cjson.decode(data.gameData.rule or "{}")
        self.roomInfo.playerNum = self.roomInfo.privateRule.playerCnt or 2
        self.roomInfo.nowPlayerNum = 1
        self.roomInfo.owner = self.roomInfo.playerids[1]
        self.roomInfo.logicData = {}
        
        if self.config then
            self.roomInfo.roomWaitingConnectTime = configPrivateRoom.PRIVATE_ROOM_WAITTING_CONNECT_TIME
            self.roomInfo.roomGameTime = configPrivateRoom.PRIVATE_ROOM_GAME_TIME
        end
    end
    
    -- 初始化玩家信息
    self:_initPrivateRoomPlayers(data)
end

-- 初始化私人房玩家
function PrivateRoom:_initPrivateRoomPlayers(data)
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
        local status = self.config.PLAYER_STATUS.LOADING
        if bRobot then
            status = self.config.PLAYER_STATUS.READY
            robotCnt = robotCnt + 1
        else
            self:setUserStatus(userid, self.gConfig.USER_STATUS.GAMEING, self.roomInfo.gameid, self.roomInfo.roomid, self.roomInfo.addr, self.roomInfo.shortRoomid)
        end
        self:checkUserInfo(userid, seat, status, bRobot)
    end
    
    self.roomInfo.robotCnt = robotCnt
end

-- 检查是否是房主
function PrivateRoom:isOwner(userid)
    return userid == self.roomInfo.owner
end

-- 玩家加入私人房
function PrivateRoom:joinPrivateRoom(userid)
    if self.roomInfo.gameStatus == self.config.GAME_STATUS.START or 
       self.roomInfo.gameStatus == self.config.GAME_STATUS.END then
        return false, "游戏已开始"
    end

    if self.roomInfo.nowPlayerNum < self.roomInfo.playerNum then
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
                self:setUserStatus(userid, self.gConfig.USER_STATUS.GAMEING, self.roomInfo.gameid, self.roomInfo.roomid, self.roomInfo.addr, self.roomInfo.shortRoomid)
                self:checkUserInfo(userid, seat, self.config.PLAYER_STATUS.LOADING, false)
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

-- 玩家离开房间
function PrivateRoom:leaveRoom(userid)
    log.info("PrivateRoom:leaveRoom userid = %d", userid)
    
    if not self:isPrivateRoom() then
        return {code = 0, msg = "非私人房间"}
    end

    if self:isRoomStatusWaittingConnect() then
        if self:isOwner(userid) then
            return {code = 1, msg = "房主离开，保留房间"}
        else
            self:playerLeave(userid)
            return {code = 1, msg = "离开成功"}
        end
    else
        return {code = 0, msg = "游戏已开始，无法离开"}
    end
end

-- 玩家离开处理
function PrivateRoom:playerLeave(userid)
    local player = self.players[userid]
    if not player then
        return
    end
    
    local seat = player.seat
    self.roomInfo.playerids[seat] = nil
    self.roomInfo.nowPlayerNum = self.roomInfo.nowPlayerNum - 1
    self.players[userid] = nil
    log.info("userid:%s leave", userid)

    -- 设置用户状态
    self:setUserStatus(userid, self.gConfig.USER_STATUS.ONLINE, 0, 0, "", 0)
    -- 通知其他玩家
    self:notifyPlayerLeave(userid, seat)
end

-- 通知玩家离开
function PrivateRoom:notifyPlayerLeave(userid, seat)
    local data = {
        userid = userid,
        seat = seat
    }
    self:sendToAllClient("playerLeave", data)
end

-- 玩家准备
function PrivateRoom:gameReady(userid, ready)
    if not self:isPrivateRoom() then
        return {code = 0, msg = "非私人房间"}
    end

    local player = self.players[userid]
    if not player then
        return {code = 0, msg = "玩家不存在"}
    end

    local status = player.status
    -- 取消准备
    if status == self.config.PLAYER_STATUS.READY and ready == 0 then 
        player.status = self.config.PLAYER_STATUS.ONLINE
        -- 通知其他玩家状态变化
        self:broadcastPlayerStatus(userid, player.status)
        return {code = 1, msg = "取消准备成功"}
    elseif ready == 1 then
        player.status = self.config.PLAYER_STATUS.READY
        
        -- 通知其他玩家状态变化
        self:broadcastPlayerStatus(userid, player.status)
        
        -- 检查是否可以开始游戏
        skynet.fork(function()
            self:testStart()
        end)
        return {code = 1, msg = "准备成功"}
    else
        return {code = 0, msg = "准备失败"}
    end
end

-- 测试是否可以开始游戏
function PrivateRoom:testStart()
    log.info("PrivateRoom:testStart")
    local readyCount = self:getReadyCnt()

    if readyCount == self.roomInfo.playerNum then
        self:startGame()
        return true
    else
        return false
    end
end

-- 开始游戏 (虚方法，由子类实现具体游戏逻辑)
function PrivateRoom:startGame()
    log.error("PrivateRoom:startGame should be implemented by subclass")
end

-- 玩家加入事件处理
function PrivateRoom:onPlayerJoin(userid)
    -- 发送房间信息给所有玩家
    for key, value in pairs(self.roomInfo.playerids) do
        if value ~= userid then
            self:sendRoomInfo(value)
            self:sendPlayerInfo(value)
        end
    end
    
    -- 发送加入通知
    self:sendPlayerEnter(userid)
end

-- 重写客户端准备方法
function PrivateRoom:clientReady(userid, args)
    log.info("PrivateRoom:clientReady userid = %d", userid)
    
    if self:isRoomStatusWaittingConnect() then
        if self:isPrivateRoom() then
            self.players[userid].status = self.config.PLAYER_STATUS.ONLINE
        else
            self.players[userid].status = self.config.PLAYER_STATUS.READY
        end
    elseif self:isRoomStatusStarting() then
        self.players[userid].status = self.config.PLAYER_STATUS.PLAYING
    end
    
    self:sendRoomInfo(userid)
    self:sendPlayerInfo(userid)
    self:sendPlayerEnter(userid)
    self:sendPlayerOtherEnter(userid)
    
    if self:isRoomStatusStarting() then
        if self.voteDisbandInfo.inProgress then
            self:relinkInDisband(userid)
        end
        -- 重连广播玩家状态
        self:broadcastPlayerStatus(userid, self.players[userid].status)
        self:relink(userid)
    elseif self:isRoomStatusWaittingConnect() then
        if not self:isPrivateRoom() then
            self:testStart()
        end
    end
end

-- 重写房间结束方法
function PrivateRoom:roomEnd(code)
    self.roomInfo.gameStatus = self.config.GAME_STATUS.END
    self.roomInfo.canDestroy = true

    if self.roomInfo.canDestroy then
        -- 通知游戏管理器销毁房间
        self:sendToAllClient("roomEnd", {code = code})
        skynet.send(self.gameManager, "lua", "destroyGame", self.roomInfo.gameid, self.roomInfo.roomid)
        
        -- 更新玩家状态
        for _, userid in pairs(self.roomInfo.playerids) do
            if not self:isRobotByUserid(userid) then
                self:setUserStatus(userid, self.gConfig.USER_STATUS.ONLINE, 0, 0, "", 0)
            end
        end
        
        -- 清除私有房间短ID
        if self:isPrivateRoom() then
            skynet.send(self.svrDB, "lua", "db", "clearPrivateRoomid", self.roomInfo.shortRoomid)
        end
    end

    local data = {
        code = code,
    }
    self:pushLog(self.config.LOG_TYPE.GAME_END, 0, cjson.encode(data))
end

-- 停止房间
function PrivateRoom:stop()
    -- 清理投票解散定时器
    if self.voteDisbandInfo.timer then
        self.voteDisbandInfo.stopTimer = true
        skynet.wakeup(self.voteDisbandInfo.timer)
        self.voteDisbandInfo.timer = nil
    end
    
    -- 归还机器人
    if self.roomInfo.gameData.robots and #self.roomInfo.gameData.robots > 0 then
        send(self.svrRobot, "returnRobots", self.roomInfo.gameData.robots)
    end

    -- 调用父类销毁方法
    self:destroy()
end

-- ==================== 投票解散功能 ====================

-- 发起投票解散
function PrivateRoom:voteDisbandRoom(userid, reason)
    log.info("PrivateRoom:voteDisbandRoom userid=%d, reason=%s", userid, reason or "")
    
    -- 1. 基础检查
    if not self:isPrivateRoom() then
        return {code = 0, msg = "非私人房间不支持投票解散"}
    end
    
    -- 游戏未开始，房主可以直接解散
    if not self:isRoomStatusStarting() then
        return self:voteDisbandNotStarting(userid, reason)
    end
    
    if not self.players[userid] then
        return {code = 0, msg = "玩家不在房间中"}
    end
    
    if self.voteDisbandInfo.inProgress then
        return {code = 0, msg = "当前有投票解散正在进行中"}
    end
    
    -- 2. 初始化投票信息
    local voteId = self:generateVoteId()
    local playerCount = self.roomInfo.nowPlayerNum
    local needAgreeCount = math.ceil(playerCount * 0.6) -- 60%向上取整
    
    self.voteDisbandInfo = {
        inProgress = true,
        stopTimer = false,
        voteId = voteId,
        initiator = userid,
        reason = reason or "",
        startTime = os.time(),
        timeLimit = configPrivateRoom.DISMISS_TIME_LIMIT + os.time(),
        votes = {},
        needAgreeCount = needAgreeCount,
        timer = nil
    }
    
    -- 3. 发起人自动投同意票
    self.voteDisbandInfo.votes[userid] = 1
    
    -- 4. 启动倒计时定时器
    self:startVoteDisbandTimer()
    
    -- 5. 广播投票开始消息
    local startData = {
        voteId = voteId,
        initiator = userid,
        reason = self.voteDisbandInfo.reason,
        timeLeft = self.voteDisbandInfo.timeLimit,
        playerCount = playerCount,
        needAgreeCount = needAgreeCount
    }
    self:sendToAllClient("voteDisbandStart", startData)
    
    -- 6. 立即发送第一次状态更新
    self:broadcastVoteDisbandUpdate()
    
    -- 7. 记录日志
    self:pushLog(self.config.LOG_TYPE.VOTE_DISBAND_START, userid, 
        cjson.encode({reason = reason, needAgreeCount = needAgreeCount}))
    
    return {code = 1, msg = "投票解散发起成功"}
end

-- 游戏未开始，投票解散
function PrivateRoom:voteDisbandNotStarting(userid, reason)
    if self.roomInfo.owner and self.roomInfo.owner == userid then
        skynet.fork(function()
            self:roomEnd(self.config.ROOM_END_FLAG.OWNER_DISBAND)
        end)
        return {code = 1, msg = "解散成功"}
    else
        return {code = 0, msg = "游戏未开始，无法发起投票解散"}
    end
end

function PrivateRoom:relinkInDisband(userid)
    self:sendVoteDisbandStart(userid)
    self:broadcastVoteDisbandUpdate()

end

-- 发送投票解散开始，单个玩家，主要用户断线重连
function PrivateRoom:sendVoteDisbandStart(userid) 
    local startData = {
        voteId = self.voteDisbandInfo.voteId,
        initiator = self.voteDisbandInfo.initiator,
        reason = self.voteDisbandInfo.reason,
        timeLeft = self.voteDisbandInfo.timeLimit,
        playerCount = self.roomInfo.nowPlayerNum,
        needAgreeCount = self.voteDisbandInfo.needAgreeCount
    }
    self:sendToOneClient(userid, "voteDisbandStart", startData)
end

-- 投票解散响应
function PrivateRoom:voteDisbandResponse(userid, voteId, agree)
    log.info("PrivateRoom:voteDisbandResponse userid=%d, voteId=%d, agree=%d", userid, voteId, agree)
    
    -- 1. 基础检查
    if not self.voteDisbandInfo.inProgress then
        return {code = 0, msg = "当前没有投票解散进行中"}
    end
    
    if self.voteDisbandInfo.voteId ~= voteId then
        return {code = 0, msg = "投票ID无效"}
    end
    
    if not self.players[userid] then
        return {code = 0, msg = "玩家不在房间中"}
    end
    
    if self.voteDisbandInfo.votes[userid] ~= nil then
        return {code = 0, msg = "已经投过票"}
    end
    
    -- 2. 记录投票
    self.voteDisbandInfo.votes[userid] = agree
    
    -- 3. 检查是否有拒绝票 - 立即结束
    if agree == 0 then
        self:endVoteDisband(0, "有玩家拒绝，投票失败")
        return {code = 1, msg = "投票成功"}
    end
    
    -- 4. 广播状态更新
    self:broadcastVoteDisbandUpdate()
    
    -- 5. 检查是否达到同意票数要求
    local agreeCount = self:getVoteAgreeCount()
    if agreeCount >= self.voteDisbandInfo.needAgreeCount then
        self:endVoteDisband(1, "投票通过，房间解散")
        return {code = 1, msg = "投票成功"}
    end
    
    return {code = 1, msg = "投票成功"}
end

-- 生成投票ID
function PrivateRoom:generateVoteId()
    -- 使用房间ID + 时间戳 + 随机数生成唯一ID
    local timestamp = os.time()
    local random = math.random(1000, 9999)
    return timestamp * 10000 + random
end

-- 启动投票解散定时器
function PrivateRoom:startVoteDisbandTimer()
    self.voteDisbandInfo.timer = skynet.fork(function()
        skynet.sleep(configPrivateRoom.DISMISS_TIME_LIMIT * 100)
        
        -- 停止
        if self.voteDisbandInfo.stopTimer then
            return
        end
        
        -- 超时处理
        if self.voteDisbandInfo.inProgress then
            self:endVoteDisband(0, "投票超时，自动取消")
        end
    end)
end

-- 广播投票状态更新
function PrivateRoom:broadcastVoteDisbandUpdate()
    if not self.voteDisbandInfo.inProgress then
        return
    end
    
    local timeLeft = self.voteDisbandInfo.timeLimit - (os.time() - self.voteDisbandInfo.startTime)
    timeLeft = math.max(0, timeLeft)
    
    -- 构建投票状态列表
    local voteInfos = {}
    for _, userid in pairs(self.roomInfo.playerids) do
        if userid and userid > 0 then
            table.insert(voteInfos, {
                userid = userid,
                vote = self.voteDisbandInfo.votes[userid] or -1  -- -1表示未投票
            })
        end
    end
    
    local updateData = {
        voteId = self.voteDisbandInfo.voteId,
        votes = voteInfos,
        agreeCount = self:getVoteAgreeCount(),
        refuseCount = self:getVoteRefuseCount(),
        timeLeft = timeLeft
    }
    
    self:sendToAllClient("voteDisbandUpdate", updateData)
end

-- 结束投票解散
function PrivateRoom:endVoteDisband(result, reason)
    if not self.voteDisbandInfo.inProgress then
        return
    end
    
    log.info("PrivateRoom:endVoteDisband result=%d, reason=%s", result, reason)
    
    -- 1. 停止定时器
    if self.voteDisbandInfo.timer then
        self.voteDisbandInfo.stopTimer = true
        skynet.wakeup(self.voteDisbandInfo.timer)
        self.voteDisbandInfo.timer = nil
    end
    
    -- 2. 构建最终投票状态
    local finalVotes = {}
    for _, userid in pairs(self.roomInfo.playerids) do
        if userid and userid > 0 then
            table.insert(finalVotes, {
                userid = userid,
                vote = self.voteDisbandInfo.votes[userid] or -1
            })
        end
    end
    
    -- 3. 广播投票结果
    local resultData = {
        voteId = self.voteDisbandInfo.voteId,
        result = result,
        reason = reason,
        agreeCount = self:getVoteAgreeCount(),
        refuseCount = self:getVoteRefuseCount(),
        votes = finalVotes
    }
    self:sendToAllClient("voteDisbandResult", resultData)
    
    -- 4. 记录日志
    self:pushLog(self.config.LOG_TYPE.VOTE_DISBAND_END, self.voteDisbandInfo.initiator,
        cjson.encode({
            result = result,
            reason = reason,
            agreeCount = resultData.agreeCount,
            refuseCount = resultData.refuseCount
        }))
    
    -- 5. 清理投票状态
    self.voteDisbandInfo.inProgress = false
    
    -- 6. 如果投票通过，解散房间
    if result == 1 then
        -- 延迟3秒解散房间，让客户端有时间处理结果
        skynet.fork(function()
            skynet.sleep(300) -- 3秒
            self:roomEnd(self.config.ROOM_END_FLAG.VOTE_DISBAND)
        end)
    end
end

-- 获取同意票数
function PrivateRoom:getVoteAgreeCount()
    local count = 0
    for _, vote in pairs(self.voteDisbandInfo.votes) do
        if vote == 1 then
            count = count + 1
        end
    end
    return count
end

-- 获取拒绝票数
function PrivateRoom:getVoteRefuseCount()
    local count = 0
    for _, vote in pairs(self.voteDisbandInfo.votes) do
        if vote == 0 then
            count = count + 1
        end
    end
    return count
end

-- 检查玩家是否可以投票
function PrivateRoom:canPlayerVote(userid)
    if not self.voteDisbandInfo.inProgress then
        return false, "当前没有投票进行中"
    end
    
    if not self.players[userid] then
        return false, "玩家不在房间中"
    end
    
    if self.voteDisbandInfo.votes[userid] ~= nil then
        return false, "已经投过票"
    end
    
    return true
end

return PrivateRoom