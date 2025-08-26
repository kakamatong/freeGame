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
    self.roomInfo.battleCnt = 1      -- 对战次数
    self.roomInfo.shortRoomid = 0    -- 短房间ID
    self.roomInfo.privateRule = nil  -- 私人房间规则
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
        self.roomInfo.battleCnt = data.gameData.battleCnt or 1
        
        if self.config then
            self.roomInfo.roomWaitingConnectTime = self.config.PRIVATE_ROOM_WAITTING_CONNECT_TIME
            self.roomInfo.roomGameTime = self.config.PRIVATE_ROOM_GAME_TIME
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
            self:setUserStatus(userid, self.gConfig.USER_STATUS.GAMEING, self.roomInfo.gameid, self.roomInfo.roomid, data.addr, self.roomInfo.shortRoomid)
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

-- 广播玩家状态
function PrivateRoom:broadcastPlayerStatus(userid, status)
    local data = {
        userid = userid,
        status = status
    }
    self:sendToAllClient("playerStatusUpdate", data)
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
    local data = {
        userid = userid,
        seat = self:getPlayerSeat(userid)
    }
    self:sendToAllClient("onPlayerEnter", data)
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
    
    if self:isRoomStatusStarting() then
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
    -- 归还机器人
    if self.roomInfo.gameData.robots and #self.roomInfo.gameData.robots > 0 then
        send(self.svrRobot, "returnRobots", self.roomInfo.gameData.robots)
    end

    -- 调用父类销毁方法
    self:destroy()
end

return PrivateRoom