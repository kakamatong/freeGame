local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local config = require "games.10001.config"
local logicHandler = require "games.10001.logic"
local aiHandler = require "games.10001.ai"
local sharedata = require "skynet.sharedata"
local core = require "sproto.core"
local sproto = require "sproto"
local gConfig = CONFIG
local roomInfo = {
    roomid = 0,
    gameid = 0,
    gameStartTime = 0,
    createRoomTime = 0,
    playerNum = 0, -- 房间最大人数
    nowPlayerNum = 0, -- 当前人数
    gameStatus = config.GAME_STATUS.NONE,
    canDestroy = false, -- 是否可以销毁
    gameData = {}, -- 游戏数据
    playerids = {}, -- 玩家id列表,index 表示座位
    robotCnt = 0, -- 机器人数量
    roomType = gConfig.ROOM_TYPE.MATCH, -- 房间类型
    owner = 0, -- 房主
    battleCnt = 1, -- 对战次数
    shortRoomid = 0, -- 短房间id
    privateRule = nil, -- 私人房间规则
    roomWaitingConnectTime = 0, -- 等待连接时间
    roomGameTime = 0, -- 游戏时间
}

local players = {}
local host
local svrGate
local reportsessionid = 0
local roomHandler = {}
local roomHandlerAi = {}
local gameManager
local send_request = nil
local dTime = 100
local svrUser = gConfig.CLUSTER_SVR_NAME.USER
local svrDB = nil
local svrRobot = gConfig.CLUSTER_SVR_NAME.ROBOT
local spc2s = nil
local sps2c = nil
-- 更新玩家状态
-- 收发协议
-- 游戏逻辑
-- 销毁逻辑
-- 未开局销毁逻辑

-- 加载sproto
local function loadSproto()
    local t = sharedata.query(config.SPROTO.C2S)
    spc2s = core.newproto(t.str)
    host = sproto.sharenew(spc2s):host "package"


    t = sharedata.query(config.SPROTO.S2C)
    sps2c = core.newproto(t.str)
    send_request = host:attach(sproto.sharenew(sps2c))
end

-- 房间日志，创建，销毁，开始，结束
local function pushLog(logtype, userid, gameid, roomid, ext)
    local time = os.time()
    local timecn = os.date("%Y-%m-%d %H:%M:%S", time)
    skynet.send(svrDB, "lua", "dbLog", "insertRoomLog", logtype, userid, gameid, roomid, timecn, ext)
end

local function getUseridByFd(fd)
    for key, value in pairs(players) do
        if value.clientFd == fd then
            return key
        end
    end
end

-- 游戏结果日志
local function pushLogResult(type, userid, gameid, roomid, result, score1, score2, score3, score4, score5, ext)
    local time = os.time()
    local timecn = os.date("%Y-%m-%d %H:%M:%S", time)
    skynet.send(svrDB, "lua", "dbLog", "insertResultLog", type, userid, gameid, roomid, result, score1, score2, score3, score4, score5, timecn, ext)
end

-- 用户游戏记录
local function pushUserGameRecords(userid, gameid, addType, addNums)
    skynet.send(svrDB, "lua", "db", "insertUserGameRecords", userid, gameid, addType, addNums)
end

-- 是否是匹配房间
local function isMatchRoom()
    return roomInfo.roomType == gConfig.ROOM_TYPE.MATCH
end

-- 是否是私人房间
local function isPrivateRoom()
    return roomInfo.roomType == gConfig.ROOM_TYPE.PRIVATE
end

local function setUserStatus(userid, status, gameid, roomid, addr, shortRoomid)
    send(svrUser, "setUserStatus", userid, status, gameid, roomid, addr, shortRoomid)
end

local function getUserStatus(userid)
    local status = call(svrUser, "userStatus", userid)
    return status
end

local function isUserOnline(userid)
    return players[userid] and players[userid].status == config.PLAYER_STATUS.PLAYING
end

local function dispatchSeat()
    for i = 1, roomInfo.playerNum do
        if not roomInfo.playerids[i] then
            return i
        end
    end
end

-- 初始化玩家信息
local function checkUserInfo(userid,seat,status,bRobot)
    if not players[userid] then
        local info = call(svrUser, "userData", userid)
        players[userid] = {
            userid = userid,
            seat = seat,
            status = status,
            isRobot = bRobot,
            info = info,
        }
    end
end

local function getOnLineCnt()
    local cnt = 0
    for _, player in pairs(players) do
        if player.status == config.PLAYER_STATUS.ONLINE then
            cnt = cnt + 1
        end
    end
    return cnt
end

-- 在初始化游戏之前，所有游戏逻辑相关配置均可以修改
local function initLogic()
    logicHandler.init(roomInfo.playerNum, roomInfo.gameData.rule, roomHandler)
    aiHandler.init(roomHandlerAi, roomInfo.robotCnt)
end

-- 开始游戏
local function startGame()
    roomInfo.gameStatus = config.GAME_STATUS.START
    roomInfo.gameStartTime = os.time()
    -- 初始化逻辑，本局游戏规则，不可再改变
    initLogic()
    logicHandler.startGame()
    pushLog(config.LOG_TYPE.GAME_START, 0, roomInfo.gameid, roomInfo.roomid, "")
    log.info("game start")
end

-- 判断是否是机器人
local function isRobotByUserid(userid)
    return players[userid].isRobot
end

-- 判断是否是机器人
local function isRobotBySeat(seat)
    local userid = roomInfo.playerids[seat]
    return isRobotByUserid(userid)
end

-- 获取玩家座位
local function getPlayerSeat(userid)
    for i, id in pairs(roomInfo.playerids) do
        if id == userid then
            return i
        end
    end
end

-- 测试是否可以开始游戏
local function testStart()
    log.info("testStart")
    local onlineCount = getOnLineCnt()

    if onlineCount == roomInfo.playerNum then
        startGame()
        return true
    else
        return false
    end
end

-- 发送消息
local function send_package(client_fd, pack)
    skynet.send(svrGate, "lua", "send", client_fd, pack)
end

-- 发送消息给单个玩家
local function sendToOneClient(userid, name, data)
    if not send_request then
        log.error("sendToOneClient error: send_request not started")
        return 
    end
    local client_fd = players[userid].clientFd
    if client_fd then
        reportsessionid = reportsessionid + 1
        send_package(client_fd, send_request(name, data, reportsessionid))
    elseif isRobotByUserid(userid) then
        -- 发给ai
        local seat = getPlayerSeat(userid)
        aiHandler.onMsg(seat, name, data)
    end
end

-- 发送消息给所有玩家
local function sendToAllClient(name, data)
    if not send_request then
        return 
    end

    for i, userid in pairs(roomInfo.playerids) do
        sendToOneClient(userid, name, data)
    end
end

-- 玩家重新连接
local function relink(userid)
    local seat = getPlayerSeat(userid)
    logicHandler.relink(seat)
end

-- 游戏结束
local function roomEnd(code)
    roomInfo.gameStatus = config.GAME_STATUS.END
    -- 清理逻辑，如果要换取相关逻辑数据，请在清理之前获取
    logicHandler.clear()

    roomInfo.canDestroy = true

    if roomInfo.canDestroy then
        --gameManager.destroyGame(gameid, roomid)
        sendToAllClient("roomEnd", {code=code})
        skynet.send(gameManager, "lua","destroyGame", roomInfo.gameid, roomInfo.roomid)
        for _, userid in pairs(roomInfo.playerids) do
            if not isRobotByUserid(userid) then
                setUserStatus(userid, gConfig.USER_STATUS.ONLINE, 0, 0, "", 0)
            end
        end
        -- 清除私有房间短ID
        if isPrivateRoom() then
            skynet.send(svrDB, "lua", "db", "clearPrivateRoomid", roomInfo.shortRoomid)
        end
    end

    local data ={
        code = code,
    }
    pushLog(config.LOG_TYPE.GAME_END, 0, roomInfo.gameid, roomInfo.roomid, cjson.encode(data))
end

-- 检查桌子状态，如果超时，则销毁桌子
local function checkRoomStatus()
    if roomInfo.gameStatus == config.GAME_STATUS.WAITTING_CONNECT then
        local timeNow = os.time()
        if timeNow - roomInfo.createRoomTime > roomInfo.roomWaitingConnectTime then
            --testStart()
            roomEnd(config.ROOM_END_FLAG.OUT_TIME_WAITING)
        end
    elseif roomInfo.gameStatus == config.GAME_STATUS.START then
        local timeNow = os.time()
        if timeNow - roomInfo.gameStartTime > roomInfo.roomGameTime then
            roomEnd(config.ROOM_END_FLAG.OUT_TIME_PLAYING)
        end
    end
end

-- 发送房间信息
local function sendRoomInfo(userid)
    local info = {
        gameid = roomInfo.gameid,
        roomid = roomInfo.roomid,
        playerids = roomInfo.playerids,
        gameData = cjson.encode(roomInfo.gameData),
    }
    local msgType = "roomInfo"
    sendToOneClient(userid, msgType, info)
end

local function sendPlayerInfo(userid)
    local data = {}
    for _, player in pairs(players) do
        data[player.seat] = player.info
        data[player.seat].status = player.status
    end

    local msgType = "playerInfos"
    sendToOneClient(userid, msgType, {infos = data})
end

local function onPlayerJoin(userid)
    for key, value in pairs(roomInfo.playerids) do
        if value ~= userid then
            sendPlayerInfo(value)
        end
    end
end

------------------------------------------------------------------------------------------------------------ ai消息处理
-- 处理ai消息
function roomHandlerAi.onAiMsg(seat, name, data)
    log.info("roomHandlerAi.onAiMsg %d, %s, %s", seat, name, UTILS.tableToString(data))
    local func = assert(logicHandler[name], "roomHandlerAi.onAiMsg not found")
    func(seat, data)
end

------------------------------------------------------------------------------------------------------------ room接口，提供给logic调用
-- room接口,发送消息给玩家
function roomHandler.logicMsg(seat, name, data)
    if 0 == seat then
        sendToAllClient(name, data)
    else
        local userid = roomInfo.playerids[seat]
        sendToOneClient(userid, name, data)
    end
    
end

-- room接口,游戏结果
function roomHandler.gameResult(data)
    local day = os.date("%Y%m%d")
    local rankKey = "game10001DayRank:" .. day
    for k, v in pairs(data) do
        local userid = roomInfo.playerids[v.seat]
        local flag = config.RESULT_TYPE.NONE
        local addType = "other"
        local score = 0
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
        local totalScore = skynet.call(svrDB,"lua", "dbRedis", "zscore", rankKey, userid) or 0
        totalScore = totalScore + score
        skynet.call(svrDB,"lua", "dbRedis", "zadd", rankKey, totalScore, userid)
        skynet.call(svrDB,"lua", "dbRedis", "expire", rankKey, 86400 * 7)

        local tmp = {
            playerids = roomInfo.playerids,
            data = data,
        }
        pushLogResult(config.LOG_RESULT_TYPE.GAME_END, userid, roomInfo.gameid, roomInfo.roomid, flag, 0, 0, 0, 0, 0, cjson.encode(tmp))

        pushUserGameRecords(userid, roomInfo.gameid, addType, 1)
    end
end

-- room接口,游戏结束
function roomHandler.gameEnd()
    roomEnd(config.ROOM_END_FLAG.GAME_END)
end

-- region 命令接口
------------------------------------------------------------------------------------------------------------ 命令接口
local CMD = {}

-- 初始化房间逻辑
function CMD.start(data)
    log.info("game10001 start %s", UTILS.tableToString(data))
    roomInfo.roomid = data.roomid
    roomInfo.gameid = data.gameid
    roomInfo.playerids = data.players
    roomInfo.gameData = data.gameData
    roomInfo.roomType = data.roomType or gConfig.ROOM_TYPE.MATCH
    roomInfo.shortRoomid = data.shortRoomid or 0
    -- 区分匹配房间和私人房间
    if isMatchRoom() then
        roomInfo.playerNum = #roomInfo.playerids
        roomInfo.nowPlayerNum = roomInfo.playerNum
        roomInfo.roomWaitingConnectTime = config.MATCH_ROOM_WAITTING_CONNECT_TIME
        roomInfo.roomGameTime = config.MATCH_ROOM_GAME_TIME
    elseif isPrivateRoom() then
        roomInfo.privateRule = cjson.decode(data.gameData.rule or "")
        roomInfo.playerNum = roomInfo.privateRule.playerCnt or 2
        roomInfo.nowPlayerNum = roomInfo.playerNum
        roomInfo.owner = roomInfo.playerids[1]
        roomInfo.battleCnt = data.gameData.battleCnt or 1
        roomInfo.roomWaitingConnectTime = config.PRIVATE_ROOM_WAITTING_CONNECT_TIME
        roomInfo.roomGameTime = config.PRIVATE_ROOM_GAME_TIME
    end
    

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
    for seat, userid in pairs(roomInfo.playerids) do
        local bRobot = isRobotFunc(userid)
        local status = config.PLAYER_STATUS.LOADING
        if bRobot then
            status = config.PLAYER_STATUS.ONLINE
            robotCnt = robotCnt + 1
        else
            setUserStatus(userid, gConfig.USER_STATUS.GAMEING, roomInfo.gameid, roomInfo.roomid, roomInfo.addr, roomInfo.shortRoomid)
        end
        checkUserInfo(userid, seat, status, bRobot)
    end

    gameManager = data.gameManager
    roomInfo.robotCnt = robotCnt
    roomInfo.createRoomTime = os.time()
    skynet.fork(function()
        while true do
            skynet.sleep(dTime)
            logicHandler.update()
            aiHandler.update()
            checkRoomStatus()
        end
    end)
    roomInfo.gameStatus = config.GAME_STATUS.WAITTING_CONNECT

    -- 创建房间日志
    local ext = {
        playerids = roomInfo.playerids,
        gameData = roomInfo.gameData
    }
    local extstr = cjson.encode(ext)
    pushLog(config.LOG_TYPE.CREATE_ROOM, 0, roomInfo.gameid, roomInfo.roomid, extstr)

    testStart()
end

-- 连接游戏
function CMD.connectGame(userid, client_fd)
    log.info("connectGame userid = %d",userid)
    if isMatchRoom() then
        for i = 1, roomInfo.playerNum do
            if roomInfo.playerids[i] == userid then
                players[userid].clientFd = client_fd
                return true
            end
        end
    elseif isPrivateRoom() then
        for _, value in pairs(roomInfo.playerids) do
            if value == userid then
                players[userid].clientFd = client_fd
                return true
            end
        end
    end
end

function CMD.joinPrivateRoom(userid)
    if roomInfo.gameStatus == config.GAME_STATUS.START or roomInfo.gameStatus == config.GAME_STATUS.END then
        return false, "游戏已开始"
    end

    if roomInfo.nowPlayerNum < roomInfo.playerNum then
        local bin = false
        for key, value in pairs(roomInfo.playerids) do
            if value == userid then
                bin = true
            end
        end

        if not bin then
            local seat = dispatchSeat()
            if seat then
                roomInfo.playerids[seat] = userid
                roomInfo.nowPlayerNum = roomInfo.nowPlayerNum + 1
                checkUserInfo(userid,seat,config.PLAYER_STATUS.LOADING,false)
                onPlayerJoin(userid)
                return true
            else
                return false,"分配座位错误"
            end
        end
    else 
        return false,"人已满"
    end
end

function CMD.stop()
    -- 清理玩家
    if roomInfo.gameData.robots and #roomInfo.gameData.robots > 0 then
        send(svrRobot, "returnRobots", roomInfo.gameData.robots)
    end

    for _, v in pairs(players) do
        if not v.isRobot and v.clientFd then
            skynet.send(svrGate, "lua", "roomOver", v.clientFd)
        end
    end

    pushLog(config.LOG_TYPE.DESTROY_ROOM, 0, roomInfo.gameid, roomInfo.roomid, "")
    
    -- 必须删除，否则会导致内存泄漏
    core.deleteproto(spc2s)
    core.deleteproto(sps2c)
    skynet.exit()
end

function CMD.socketClose(fd)
    local userid = getUseridByFd(fd)
    if roomInfo.gameStatus == config.GAME_STATUS.WAITTING_CONNECT then
        players[userid].status = config.PLAYER_STATUS.LOADING
    else
        players[userid].status = config.PLAYER_STATUS.OFFLINE
    end
end

------------------------------------------------------------------------------------------------------------
local REQUEST = {}
function REQUEST:clientReady(userid, args)
    log.info("clientReady userid = %d",userid)
    -- 私人房模式需要拉去玩家信息
    if roomInfo.gameStatus == config.GAME_STATUS.WAITTING_CONNECT then
        players[userid].status = config.PLAYER_STATUS.ONLINE
    elseif roomInfo.gameStatus == config.GAME_STATUS.START then
        players[userid].status = config.PLAYER_STATUS.PLAYING
    end
    sendRoomInfo(userid)
    sendPlayerInfo(userid)
    if roomInfo.gameStatus == config.GAME_STATUS.START then
        relink(userid)
    elseif roomInfo.gameStatus == config.GAME_STATUS.WAITTING_CONNECT then
        testStart()
    end
end

function REQUEST:outHand(userid, args)
    local seat = getPlayerSeat(userid)
    logicHandler.outHand(seat, args)
end

-- 客户端请求分发
local function request(fd, name, args, response)
	local userid = getUseridByFd(fd)
    if not userid then
        log.error("request fd %d not found userid", fd)
        return
    end
    local func = assert(REQUEST[name])
    local res = func(REQUEST, userid, args)
    if response then
        return response(res)
    end
	
end

-- 注册客户端协议，处理客户端消息
skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		--log.info("agent unpack msg %s, sz %d", type(msg), sz)
		local str = skynet.tostring(msg, sz)
		return host:dispatch(str, sz)
	end,
	dispatch = function (fd, _, type, ...)
		log.info("room dispatch fd %d, type %s", fd, type)
		--assert(fd == client_fd) -- 只能处理自己的fd
		skynet.ignoreret() -- session是fd，不需要返回
		if type == "REQUEST" then
			local ok, result  = pcall(request, fd, ...)
			if ok then
				if result then
					send_package(fd, result)
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

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        end
    end)
    loadSproto()
    svrGate = skynet.localname(CONFIG.SVR_NAME.GAME_GATE)
    svrDB = skynet.localname(CONFIG.SVR_NAME.DB)
end)
