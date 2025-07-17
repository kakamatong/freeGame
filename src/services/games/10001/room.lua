local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local config = require "games.10001.config"
require "skynet.manager"
local logicHandler = require "games.10001.logic"
local sprotoloader = require "sprotoloader"
local aiHandler = require "games.10001.ai"
local sharedata = require "skynet.sharedata"
local core = require "sproto.core"
local sproto = require "sproto"
local roomid = 0
local gameid = 0
local playerids = {} -- 玩家id列表,index 表示座位
local gameData = {} -- 游戏数据
local onlines = {} -- 玩家在线状态
local client_fds = {} -- 玩家连接信息
local canDestroy = false -- 是否可以销毁
local createRoomTime = 0
local host
local gate
local gameStatus = config.GAME_STATUS.NONE
local reportsessionid = 0
local gameStartTime = 0
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
    for key, value in pairs(client_fds) do
        if value == fd then
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

-- 开始游戏
local function startGame()
    gameStatus = config.GAME_STATUS.START
    gameStartTime = os.time()
    logicHandler.startGame()
    pushLog(config.LOG_TYPE.GAME_START, 0, gameid, roomid, "")
    log.info("game start")
end

-- 判断是否是机器人
local function isRobotByUserid(userid)
    if gameData.robots and #gameData.robots > 0 and userid and userid > 0 then
        for _, id in pairs(gameData.robots) do
            if id == userid then
                return true
            end
        end
    end
    return false
end

-- 判断是否是机器人
local function isRobotBySeat(seat)
    local userid = playerids[seat]
    return isRobotByUserid(userid)
end

-- 获取玩家座位
local function getPlayerSeat(userid)
    for i, id in pairs(playerids) do
        if id == userid then
            return i
        end
    end
end

-- 测试是否可以开始游戏
local function testStart()
    log.info("testStart")
    local onlineCount = 0
    for _, playerid in pairs(playerids) do
        if onlines[playerid] ~= nil then
            onlineCount = onlineCount + 1
        else
            return false
        end
    end

    if onlineCount == #playerids then
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
    local client_fd = client_fds[userid]
    if client_fd and onlines[userid] then
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

    for i, userid in pairs(playerids) do
        sendToOneClient(userid, name, data)
    end
end

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

-- 玩家连入游戏，玩家客户端准备就绪
local function online(userid)
    onlines[userid] = true
    if gameStatus == config.GAME_STATUS.WAITTING_CONNECT then
        --gameStatus = gameStatus.START
        testStart()
    elseif gameStatus == config.GAME_STATUS.START then
        relink(userid)
    end
end

-- 游戏结束
local function gameEnd()
    gameStatus = config.GAME_STATUS.END
    canDestroy = true

    if canDestroy then
        --gameManager.destroyGame(gameid, roomid)
        skynet.send(gameManager, "lua", "destroyGame", gameid, roomid)
    end
    pushLog(config.LOG_TYPE.GAME_END, 0, gameid, roomid, "")
end

-- 检查桌子状态，如果超时，则销毁桌子
local function checkRoomStatus()
    if gameStatus == config.GAME_STATUS.WAITTING_CONNECT then
        local timeNow = os.time()
        if timeNow - createRoomTime > config.WAITTING_CONNECT_TIME then
            --testStart()
            gameEnd()
        end
    elseif gameStatus == config.GAME_STATUS.START then
        local timeNow = os.time()
        if timeNow - gameStartTime > config.GAME_TIME then
            gameEnd()
        end
    end
end

local function sendRoomInfo(userid)
    local info = {
        gameid = gameid,
        roomid = roomid,
        playerids = playerids,
        gameData = gameData
    }
    local msgType = "roomInfo"
    svrMsg(userid, msgType, info)
end

------------------------------------------------------------------------------------------------------------ ai消息处理
-- 处理ai消息
function roomHandlerAi.onAiMsg(seat, name, data)
    log.info("roomHandlerAi.onMsg", seat, name, data)
    -- local f = XY[name]
    -- if f then
    --     local userid = playerids[seat]
    --     f(userid, data)
    -- end
end

------------------------------------------------------------------------------------------------------------ room接口，提供给logic调用
-- room接口,发送消息给单个玩家
function roomHandler.sendToOneClient(seat, name, data)
    local userid = playerids[seat]
    sendToOneClient(userid, name, data)
end

-- room接口,发送消息给所有玩家
function roomHandler.sendToAllClient(name, data)
    sendToAllClient(name, data)
end

-- room接口,游戏结果
function roomHandler.gameResult(data)
    for k, v in pairs(data) do
        local userid = playerids[v.seat]
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
            playerids = playerids,
            data = data,
        }
        pushLogResult(config.LOG_RESULT_TYPE.GAME_END, userid, gameid, roomid, flag, 0, 0, 0, 0, 0, cjson.encode(tmp))

        pushUserGameRecords(userid, gameid, addType, 1)
    end
end

-- room接口,游戏结束
function roomHandler.gameEnd()
    gameEnd()
end

-- region 命令接口
------------------------------------------------------------------------------------------------------------ 命令接口
local CMD = {}

-- 初始化游戏逻辑
function CMD.start(data)
    log.info("game10001 start %s", UTILS.tableToString(data))
    roomid = data.roomid
    gameid = data.gameid
    playerids = data.players
    gameData = data.gameData
    gameManager = data.gameManager
    logicHandler.init(#playerids, gameData.rule, roomHandler)
    aiHandler.init(roomHandlerAi)
    createRoomTime = os.time()
    skynet.fork(function()
        while true do
            skynet.sleep(dTime)
            logicHandler.update()
            aiHandler.update()
            checkRoomStatus()
        end
    end)
    gameStatus = config.GAME_STATUS.WAITTING_CONNECT

    -- 创建房间日志
    local ext = {
        playerids = playerids,
        gameData = gameData
    }
    local extstr = cjson.encode(ext)
    pushLog(config.LOG_TYPE.CREATE_ROOM, 0, gameid, roomid, extstr)
end

-- 连接游戏
function CMD.connectGame(userid, client_fd)
    for i = 1, #playerids do
        if playerids[i] == userid then
            client_fds[userid] = client_fd
            online(userid)
            return true
        end
    end
end

function CMD.stop()
    -- 清理玩家
    if gameData.robots and #gameData.robots > 0 then
        local robotManager = skynet.localname(".robotManager")
        if robotManager then
            skynet.send(robotManager, "lua", "returnRobots", gameData.robots)
        end
    end

    pushLog(config.LOG_TYPE.DESTROY_ROOM, 0, gameid, roomid, "")
    skynet.exit()
end

function CMD.offLine(userid)
    if onlines[userid] then
        onlines[userid] = false
    end
end
------------------------------------------------------------------------------------------------------------
local REQUEST = {}
function REQUEST:clientReady(userid, args)
    sendRoomInfo(userid)
    return {msg = "success"}
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

	end
end

local function clientSend(moduleName, funcName, userid, args)
	if moduleName == "room" then
		local f = assert(REQUEST[funcName])
        f(REQUEST, userid, args)
	elseif moduleName == "logic" then

	end
end

-- 客户端请求分发
local function request(fd, name, args, response)
	--log.info("request %d %s", fd, UTILS.tableToString(client_fds))
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