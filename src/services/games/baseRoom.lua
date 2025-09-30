--[[
    BaseRoom模块 - 房间基础功能
    功能：
    1. 房间状态管理
    2. 玩家管理
    3. 消息收发机制
    4. 协议处理
    5. 日志记录
    6. 房间超时检查
]]

local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local sharedata = require "skynet.sharedata"
local core = require "sproto.core"
local sproto = require "sproto"

local BaseRoom = {}
BaseRoom.__index = BaseRoom

-- 构造函数
function BaseRoom:new()
    local obj = {}
    setmetatable(obj, self)
    obj:_init()
    return obj
end

-- 初始化
function BaseRoom:_init()
    -- 房间信息
    self.roomInfo = {
        roomid = 0,
        gameid = 0,
        gameStartTime = 0,
        createRoomTime = 0,
        playerNum = 0, -- 房间最大人数
        nowPlayerNum = 0, -- 当前人数
        gameStatus = 0, -- 游戏状态 (NONE, WAITTING_CONNECT, START, END)
        canDestroy = false, -- 是否可以销毁
        gameData = {}, -- 游戏数据
        playerids = {}, -- 玩家id列表,index 表示座位
        robotCnt = 0, -- 机器人数量
        roomType = 0, -- 房间类型 (MATCH, PRIVATE)
        roomWaitingConnectTime = 0, -- 等待连接时间
        roomGameTime = 0, -- 游戏时间
        addr = "",
        playedCnt = 0, -- 玩过的次数
        logicData = {},
    }
    
    -- 玩家信息
    self.players = {}
    
    -- 服务相关
    self.host = nil
    self.svrGate = nil
    self.reportsessionid = 0
    self.gameManager = nil
    self.send_request = nil
    self.dTime = 100
    self.spc2s = nil
    self.sps2c = nil
    
    -- 常量引用
    self.gConfig = CONFIG
    self.config = nil -- 由子类设置具体游戏配置
    
    -- 服务名
    self.svrUser = CONFIG.CLUSTER_SVR_NAME.USER
    self.svrDB = nil
    self.svrRobot = CONFIG.CLUSTER_SVR_NAME.ROBOT
end

-- 初始化房间数据
function BaseRoom:init(data)
    log.info("BaseRoom:init %s", UTILS.tableToString(data))
    
    self.roomInfo.roomid = data.roomid
    self.roomInfo.gameid = data.gameid
    self.roomInfo.playerids = data.players
    self.roomInfo.gameData = data.gameData
    self.roomInfo.roomType = data.roomType or self.gConfig.ROOM_TYPE.MATCH
    self.roomInfo.addr = data.addr
    self.gameManager = data.gameManager
    self.roomInfo.createRoomTime = os.time()
    self.roomInfo.logicData = {}
    
    -- 初始化服务引用
    self.svrGate = skynet.localname(CONFIG.SVR_NAME.GAME_GATE)
    self.svrDB = skynet.localname(CONFIG.SVR_NAME.DB)
end

-- 加载sproto协议
function BaseRoom:loadSproto()
    if not self.config or not self.config.SPROTO then
        log.error("BaseRoom:loadSproto config.SPROTO not found")
        return
    end
    
    local t = sharedata.query(self.config.SPROTO.C2S)
    self.spc2s = core.newproto(t.str)
    self.host = sproto.sharenew(self.spc2s):host "package"

    t = sharedata.query(self.config.SPROTO.S2C)
    self.sps2c = core.newproto(t.str)
    self.send_request = self.host:attach(sproto.sharenew(self.sps2c))
end

-- 房间日志记录
function BaseRoom:pushLog(logtype, userid, ext)
    local time = os.time()
    local timecn = os.date("%Y-%m-%d %H:%M:%S", time)
    skynet.send(self.svrDB, "lua", "dbLog", "insertRoomLog", logtype, userid, self.roomInfo.gameid, self.roomInfo.roomid, timecn, ext)
end

-- 游戏结果日志
function BaseRoom:pushLogResult(type, userid, result, score1, score2, score3, score4, score5, ext)
    local time = os.time()
    local timecn = os.date("%Y-%m-%d %H:%M:%S", time)
    skynet.send(self.svrDB, "lua", "dbLog", "insertResultLog", type, userid, self.roomInfo.gameid, self.roomInfo.roomid, result, score1, score2, score3, score4, score5, timecn, ext)
end

-- 用户游戏记录
function BaseRoom:pushUserGameRecords(userid, addType, addNums)
    skynet.send(self.svrDB, "lua", "db", "insertUserGameRecords", userid, self.roomInfo.gameid, addType, addNums)
end

-- 根据fd获取用户ID
function BaseRoom:getUseridByFd(fd)
    for key, value in pairs(self.players) do
        if value.clientFd == fd then
            return key
        end
    end
    return nil
end

-- 房间状态检查方法
function BaseRoom:isRoomStatus(status)
    return self.roomInfo.gameStatus == status
end

function BaseRoom:isRoomStatusWaittingConnect()
    return self:isRoomStatus(self.config.GAME_STATUS.WAITTING_CONNECT)
end

function BaseRoom:isRoomStatusStarting()
    return self:isRoomStatus(self.config.GAME_STATUS.START)
end

function BaseRoom:isMatchRoom()
    return self.roomInfo.roomType == self.gConfig.ROOM_TYPE.MATCH
end

function BaseRoom:isPrivateRoom()
    return self.roomInfo.roomType == self.gConfig.ROOM_TYPE.PRIVATE
end

-- 玩家状态管理
function BaseRoom:setPlayerStatusByUserid(userid, status)
    if self.players[userid] then
        self.players[userid].status = status
    end
end

function BaseRoom:setPlayerStatusBySeat(seat, status)
    local userid = self.roomInfo.playerids[seat]
    if userid and self.players[userid] then
        self.players[userid].status = status
    end
end

function BaseRoom:setUserStatus(userid, status, gameid, roomid, addr, shortRoomid)
    send(self.svrUser, "setUserStatus", userid, status, gameid, roomid, addr, shortRoomid)
end

function BaseRoom:getUserStatus(userid)
    return call(self.svrUser, "userStatus", userid)
end

function BaseRoom:isUserOnline(userid)
    return self.players[userid] and self.players[userid].status == self.config.PLAYER_STATUS.PLAYING
end

function BaseRoom:isRobotByUserid(userid)
    return self.players[userid] and self.players[userid].isRobot
end

function BaseRoom:isRobotBySeat(seat)
    local userid = self.roomInfo.playerids[seat]
    return userid and self:isRobotByUserid(userid)
end

-- 获取玩家座位
function BaseRoom:getPlayerSeat(userid)
    for i, id in pairs(self.roomInfo.playerids) do
        if id == userid then
            return i
        end
    end
    return nil
end

-- 座位分配
function BaseRoom:dispatchSeat()
    for i = 1, self.roomInfo.playerNum do
        if not self.roomInfo.playerids[i] then
            return i
        end
    end
    return nil
end

-- 初始化玩家信息
function BaseRoom:checkUserInfo(userid, seat, status, bRobot)
    if not self.players[userid] then
        local info = call(self.svrUser, "userData", userid)
        self.players[userid] = {
            userid = userid,
            seat = seat,
            status = status,
            isRobot = bRobot,
            info = info,
        }
    end
end

-- 获取在线玩家数量
function BaseRoom:getOnLineCnt()
    local cnt = 0
    for _, player in pairs(self.players) do
        if player.status == self.config.PLAYER_STATUS.ONLINE then
            cnt = cnt + 1
        end
    end
    return cnt
end

-- 获取准备玩家数量
function BaseRoom:getReadyCnt()
    local cnt = 0
    for _, player in pairs(self.players) do
        if player.status == self.config.PLAYER_STATUS.READY then
            cnt = cnt + 1
        end
    end
    return cnt
end

-- 消息发送
function BaseRoom:send_package(client_fd, pack)
    skynet.send(self.svrGate, "lua", "send", client_fd, pack)
end

-- 发送消息给单个玩家
function BaseRoom:sendToOneClient(userid, name, data)
    if not self.send_request then
        log.error("sendToOneClient error: send_request not started")
        return 
    end
    
    local player = self.players[userid]
    if not player then
        log.error("sendToOneClient error: player %s not found", userid)
        return
    end
    
    local client_fd = player.clientFd
    if client_fd then
        self.reportsessionid = self.reportsessionid + 1
        self:send_package(client_fd, self.send_request(name, data, self.reportsessionid))
    elseif self:isRobotByUserid(userid) then
        -- 发给AI处理
        local seat = self:getPlayerSeat(userid)
        if seat and self.aiHandler then
            self.aiHandler.onMsg(seat, name, data)
        end
    end
end

-- 发送消息给所有玩家
function BaseRoom:sendToAllClient(name, data)
    if not self.send_request then
        log.error("sendToAllClient error: send_request not started")
        return 
    end

    for i, userid in pairs(self.roomInfo.playerids) do
        self:sendToOneClient(userid, name, data)
    end
end

-- 广播玩家状态
function BaseRoom:broadcastPlayerStatus(userid, status)
    local data = {
        userid = userid,
        status = status
    }
    self:sendToAllClient("playerStatusUpdate", data)
end

-- 发送房间信息
function BaseRoom:sendRoomInfo(userid)
    local info = {
        gameid = self.roomInfo.gameid,
        roomid = self.roomInfo.roomid,
        playerids = self.roomInfo.playerids,
        gameData = cjson.encode(self.roomInfo.gameData),
        shortRoomid = self.roomInfo.shortRoomid or 0,
        owner = self.roomInfo.owner or 0
    }
    self:sendToOneClient(userid, "roomInfo", info)
end

-- 发送玩家信息
function BaseRoom:sendPlayerInfo(userid)
    local data = {}
    for _, player in pairs(self.players) do
        data[player.seat] = player.info
        data[player.seat].status = player.status
    end
    self:sendToOneClient(userid, "playerInfos", {infos = data})
end

-- 发送玩家进入
function BaseRoom:sendPlayerEnter(userid)
    local data = {
        userid = userid,
        seat = self.players[userid].seat
    }

    self:sendToAllClient("playerEnter", data)
end

-- 发送房间里其他玩家进入
function BaseRoom:sendPlayerOtherEnter(userid)
    for key, value in pairs(self.roomInfo.playerids) do
        if value ~= userid then
            local data = {
                userid = value,
                seat = key
            }

            self:sendToOneClient(userid, "playerEnter", data)
        end
    end
    
end

-- 检查房间超时
function BaseRoom:checkRoomTimeout()
    if self:isRoomStatusWaittingConnect() then
        local timeNow = os.time()
        if timeNow - self.roomInfo.createRoomTime > self.roomInfo.roomWaitingConnectTime then
            self:roomEnd(self.config.ROOM_END_FLAG.OUT_TIME_WAITING)
        end
    elseif self:isRoomStatusStarting() then
        local timeNow = os.time()
        if timeNow - self.roomInfo.gameStartTime > self.roomInfo.roomGameTime then
            self:roomEnd(self.config.ROOM_END_FLAG.OUT_TIME_PLAYING)
        end
    end
end

-- 房间结束 (虚方法，由子类实现)
function BaseRoom:roomEnd(code)
    log.error("BaseRoom:roomEnd should be implemented by subclass")
end

-- 销毁房间资源
function BaseRoom:destroy()
    -- 清理协议资源
    if self.spc2s then
        core.deleteproto(self.spc2s)
    end
    if self.sps2c then
        core.deleteproto(self.sps2c)
    end
    
    -- 清理玩家连接
    for _, v in pairs(self.players) do
        if not v.isRobot and v.clientFd then
            skynet.send(self.svrGate, "lua", "roomOver", v.clientFd)
        end
    end
    
    -- 记录销毁日志
    self:pushLog(self.config.LOG_TYPE.DESTROY_ROOM, 0, "")
    
    skynet.exit()
end

-- 连接游戏 (基础实现)
function BaseRoom:connectGame(userid, client_fd)
    log.info("BaseRoom:connectGame userid = %d", userid)
    
    for i, playerid in pairs(self.roomInfo.playerids) do
        if playerid == userid then
            if self.players[userid] then
                self.players[userid].clientFd = client_fd
                return true
            end
        end
    end
    return false
end

-- 处理socket关闭
function BaseRoom:socketClose(fd)
    local userid = self:getUseridByFd(fd)
    if not self.players[userid] then
        return
    end

    if self:isRoomStatusWaittingConnect() then
        self:changePlayerStatus(userid, self.config.PLAYER_STATUS.LOADING)
    else
        self:changePlayerStatus(userid, self.config.PLAYER_STATUS.OFFLINE)
    end
end

-- 客户端准备 (基础实现)
function BaseRoom:clientReady(userid, args)
    log.info("BaseRoom:clientReady userid = %d", userid)
    
    if self:isRoomStatusWaittingConnect() then
        self.players[userid].status = self.config.PLAYER_STATUS.READY
    elseif self:isRoomStatusStarting() then
        self.players[userid].status = self.config.PLAYER_STATUS.PLAYING
    end

    self:sendRoomInfo(userid)
    self:sendPlayerInfo(userid)
    self:sendPlayerEnter(userid)

    if self:isRoomStatusStarting() then
        self:relink(userid)
    end
end

function BaseRoom:changePlayerStatus(userid, status)
    local preStatus = self.players[userid].status
    self.players[userid].status = status
    if preStatus ~= status then
        self:broadcastPlayerStatus(userid, status)
    end
end

-- 玩家重连 (虚方法，由子类实现)
function BaseRoom:relink(userid)
    -- 基础实现为空，由游戏特定逻辑处理
end

-- 处理客户端消息 (通用消息分发)
function BaseRoom:handleClientMessage(fd, name, args, response)
    local userid = self:getUseridByFd(fd)
    if not userid then
        log.error("handleClientMessage fd %d not found userid", fd)
        return
    end
    
    -- 检查方法是否存在
    local func = self[name]
    if not func then
        log.error("handleClientMessage method %s not found", name)
        return
    end
    
    -- 调用对应方法
    local res = func(self, userid, args)
    if response and res then
        return response(res)
    end
end

return BaseRoom