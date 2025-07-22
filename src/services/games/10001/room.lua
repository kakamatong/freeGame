local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local config = require "games.10001.config"
require "skynet.manager"
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
    playerNum = 0,
    gameStatus = config.GAME_STATUS.NONE,
    canDestroy = false, -- 是否可以销毁
    gameData = {}, -- 游戏数据
    playerids = {} -- 玩家id列表,index 表示座位
}

local players = {}
local host
local gate
local reportsessionid = 0
local roomHandler = {}
local roomHandlerAi = {}
local gameManager
local send_request = nil
local dTime = 100
-- 更新玩家状态
-- 收发协议
-- 游戏逻辑
-- 销毁逻辑
-- 未开局销毁逻辑

-- 加载sproto
local function loadSproto()
    local t = sharedata.query(config.SPROTO.C2S)
    local sp = core.newproto(t.str)
    host = sproto.sharenew(sp):host "package"

    t = sharedata.query(config.SPROTO.S2C)
    sp = core.newproto(t.str)
    send_request = host:attach(sproto.sharenew(sp))
end

-- 房间日志，创建，销毁，开始，结束
local function pushLog(logtype, userid, gameid, roomid, ext)
    local dbserver = skynet.localname(".db")
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end

    local time = os.time()
    local timecn = os.date("%Y-%m-%d %H:%M:%S", time)
    skynet.send(dbserver, "lua", "dbLog", "insertRoomLog", logtype, userid, gameid, roomid, timecn, ext)
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
    local dbserver = skynet.localname(".db")
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end

    local time = os.time()
    local timecn = os.date("%Y-%m-%d %H:%M:%S", time)
    skynet.send(dbserver, "lua", "dbLog", "insertResultLog", type, userid, gameid, roomid, result, score1, score2, score3, score4, score5, timecn, ext)
end

-- 用户游戏记录
local function pushUserGameRecords(userid, gameid, addType, addNums)
    local dbserver = skynet.localname(".db")
	if not dbserver then
		log.error("wsgate login error: dbserver not started")
		return
	end
    skynet.send(dbserver, "lua", "db", "insertUserGameRecords", userid, gameid, addType, addNums)
end

local function setUserStatus(userid, status, gameid, roomid)
    local svrUser = skynet.localname(".user")
    if not svrUser then
        return
    end
    local data = {
        status = status,
        gameid = gameid,
        roomid = roomid,
    }
    skynet.send(svrUser, "lua", "svrCall" , "user", "setUserStatus", userid, data)
end

local function getUserStatus(userid)
    local svrUser = skynet.localname(".user")
    if not svrUser then
        return
    end
    local status = skynet.call(svrUser, "lua", "svrCall", "user", "userStatus", userid)
    return status
end

local function isUserOnline(userid)
    return players[userid] and players[userid].status == config.PLAYER_STATUS.PLAYING
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

-- 开始游戏
local function startGame()
    roomInfo.gameStatus = config.GAME_STATUS.START
    roomInfo.gameStartTime = os.time()
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
    skynet.send(gate, "lua", "send", client_fd, pack)
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
        aiHandler.onMsg(seat, data.type, cjson.decode(data.data))
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

-- 发送服务消息
local function svrMsg(userid, msgType, info)
    local data = {
        type = msgType or "",
        data = cjson.encode(info),
    }
    if userid == 0 then
        sendToAllClient("svrMsg", data)
        return
    end

    sendToOneClient(userid, "svrMsg", data)
end

-- 玩家重新连接
local function relink(userid)
    local seat = getPlayerSeat(userid)
    logicHandler.relink(seat)
end

-- 游戏结束
local function roomEnd(code)
    roomInfo.gameStatus = config.GAME_STATUS.END
    roomInfo.canDestroy = true

    if roomInfo.canDestroy then
        --gameManager.destroyGame(gameid, roomid)
        svrMsg(0, "roomEnd", {code=code})
        skynet.send(gameManager, "lua", "destroyGame", roomInfo.gameid, roomInfo.roomid)
        for _, userid in pairs(roomInfo.playerids) do
            if not isRobotByUserid(userid) then
                setUserStatus(userid, gConfig.USER_STATUS.ONLINE, 0, 0)
            end
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
        if timeNow - roomInfo.createRoomTime > config.WAITTING_CONNECT_TIME then
            --testStart()
            roomEnd(config.ROOM_END_FLAG.OUT_TIME_WAITING)
        end
    elseif roomInfo.gameStatus == config.GAME_STATUS.START then
        local timeNow = os.time()
        if timeNow - roomInfo.gameStartTime > config.GAME_TIME then
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
        gameData = roomInfo.gameData
    }
    local msgType = "roomInfo"
    svrMsg(userid, msgType, info)
end

------------------------------------------------------------------------------------------------------------ ai消息处理
-- 处理ai消息
function roomHandlerAi.onAiMsg(seat, name, data)
    log.info("roomHandlerAi.onMsg", seat, name, data)
    logicHandler.clientMsg(seat, name, data)
end

------------------------------------------------------------------------------------------------------------ room接口，提供给logic调用
-- room接口,发送消息给玩家
function roomHandler.svrMsg(seat, name, data)
    if 0 == seat then
        svrMsg(0, name, data)
    else
        local userid = roomInfo.playerids[seat]
        svrMsg(userid, name, data)
    end
    
end

-- room接口,游戏结果
function roomHandler.gameResult(data)
    for k, v in pairs(data) do
        local userid = roomInfo.playerids[v.seat]
        local flag = config.RESULT_TYPE.NONE
        local addType = "other"
        if v.endResult == 1 then
            flag = config.RESULT_TYPE.WIN
            addType = "win"
        elseif v.endResult == 2 then
            flag = config.RESULT_TYPE.DRAW
            addType = "draw"
        else 
            flag = config.RESULT_TYPE.LOSE
            addType = "lose"
        end
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

-- 初始化游戏逻辑
function CMD.start(data)
    log.info("game10001 start %s", UTILS.tableToString(data))
    roomInfo.roomid = data.roomid
    roomInfo.gameid = data.gameid
    roomInfo.playerids = data.players
    roomInfo.gameData = data.gameData
    roomInfo.playerNum = #roomInfo.playerids

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
        else
            setUserStatus(userid, gConfig.USER_STATUS.GAMEING, roomInfo.gameid, roomInfo.roomid)
        end
        players[userid] = {
            userid = userid,
            seat = seat,
            status = status,
            isRobot = bRobot,
        }
    end
    gameManager = data.gameManager
    logicHandler.init(roomInfo.playerNum, roomInfo.gameData.rule, roomHandler)
    aiHandler.init(roomHandlerAi)
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
end

-- 连接游戏
function CMD.connectGame(userid, client_fd)
    log.info("connectGame userid = %d",userid)
    for i = 1, roomInfo.playerNum do
        if roomInfo.playerids[i] == userid then
            players[userid].clientFd = client_fd
            return true
        end
    end
end

function CMD.stop()
    -- 清理玩家
    if roomInfo.gameData.robots and #roomInfo.gameData.robots > 0 then
        local robot = skynet.localname(".robot")
        if robot then
            skynet.send(robot, "lua", "svrCall", "robot", "returnRobots", roomInfo.gameData.robots)
        end
    end

    for _, v in pairs(players) do
        if not v.isRobot and v.clientFd then
            skynet.send(gate, "lua", "roomOver", v.clientFd)
        end
    end

    pushLog(config.LOG_TYPE.DESTROY_ROOM, 0, roomInfo.gameid, roomInfo.roomid, "")
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
    if roomInfo.gameStatus == config.GAME_STATUS.WAITTING_CONNECT then
        players[userid].status = config.PLAYER_STATUS.ONLINE
    elseif roomInfo.gameStatus == config.GAME_STATUS.START then
        players[userid].status = config.PLAYER_STATUS.PLAYING
    end
    sendRoomInfo(userid)
    if roomInfo.gameStatus == config.GAME_STATUS.START then
        relink(userid)
    elseif roomInfo.gameStatus == config.GAME_STATUS.WAITTING_CONNECT then
        testStart()
    end
end

local function clientCall(moduleName, funcName, userid, args)
	if moduleName == "room" then
		local f = assert(REQUEST[funcName])
        local res ={
            code = 1,
            result = cjson.encode(f(REQUEST, userid, args)),
        }
		return res
	elseif moduleName == "logic" then
        local seat = getPlayerSeat(userid)
        local data = logicHandler.clientMsg(seat, funcName, args)
        local res ={
            code = 1,
            result = cjson.encode(data),
        }
		return res
	end
end

local function clientSend(moduleName, funcName, userid, args)
	if moduleName == "room" then
		local f = assert(REQUEST[funcName])
        f(REQUEST, userid, args)
	elseif moduleName == "logic" then
        local seat = getPlayerSeat(userid)
        logicHandler.clientMsg(seat, funcName, args)
	end
end

-- 客户端请求分发
local function request(fd, name, args, response)
	local userid = getUseridByFd(fd)
    if not userid then
        log.error("request fd %d not found userid", fd)
        return
    end
    if name == "call" then
        local r = clientCall(args.moduleName, args.funcName, userid, cjson.decode(args.args))
        if response then
            return response(r)
        end
    elseif name == "send" then
        clientSend(args.moduleName, args.funcName, userid, cjson.decode(args.args))
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
    gate = skynet.localname(".wsGameGateserver")
end)