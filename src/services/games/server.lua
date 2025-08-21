--[[
游戏服务管理器模块
负责游戏房间的创建、销毁、玩家连接等核心功能
]]
local skynet = require "skynet"
local log = require "log"
local CMD = {}                    -- 命令表，用于处理外部调用
local allGames = {}               -- 存储所有游戏房间 {gameid: {roomid: room_service_address}}
local snowflake = require "snowflake"  -- 雪花算法，用于生成唯一房间ID
local config = require "games.config"  -- 游戏配置
local sharedata = require "skynet.sharedata"  -- 共享数据模块
local parser = require "sprotoparser"  -- sproto协议解析器
local gConfig = CONFIG
require "skynet.manager"          -- 服务注册模块
local svrDB = nil
local addr = ""
--[[
加载文件内容
@param filename 文件名
@return 文件内容
]]
local function loadfile(filename)
    local f = assert(io.open(filename), "Can't open sproto file")
    local data = f:read "a"
    f:close()
    return parser.parse(data)
end

--[[
加载游戏sproto协议
遍历配置中的所有游戏ID，加载对应的c2s和s2c协议
并将协议数据共享到sharedata中
]]
local function loadSproto()
    for _, gameid in ipairs(config.gameids) do
        local filename = "proto/" .. string.format("game%d", gameid) .. "/c2s.sproto"
        local bin = loadfile(filename)
        local data = {
            str = bin,
        }
        local c2s = "game" .. gameid .. "_c2s"
        sharedata.new(c2s, data)
        --sharedata.query(c2s)

        filename = "proto/" .. string.format("game%d", gameid) .. "/s2c.sproto"
        bin = loadfile(filename)
        data = {
            str = bin,
        }
        local s2c = "game" .. gameid .. "_s2c"
        sharedata.new(s2c, data)
        --sharedata.query(s2c)
    end
end

--[[
启动函数
初始化协议加载
]]
local function start()
    local ok,err = pcall(loadSproto)
    if not ok then
        log.error("loadSproto error %s", err)
    end
end

--[[
检查房间是否存在
@param gameid 游戏ID
@param roomid 房间ID
@return 存在返回true和房间地址，不存在返回false
]]
local function checkHaveRoom(gameid, roomid)
    local games = allGames[gameid]
    if not allGames[gameid] then
        return false
    end
    local room = games[roomid]
    if not room then
        return false
    end

    return true, room
end

--[[
创建游戏房间
@param gameid 游戏ID
@param players 玩家列表
@param gameData 游戏数据
@return roomid 房间ID, addr 服务地址
]]
local function createGameRoom(roomType, gameid, players, gameData)
    local roomid = snowflake.generate()  -- 使用雪花算法生成唯一房间ID
    local name = "games/" .. gameid .. "/room"
    local shortRoomid = 0
    if roomType == gConfig.ROOM_TYPE.PRIVATE then
        for i = 1,5 do
            shortRoomid = skynet.call(svrDB, "lua", "db", "getPrivateShortRommid", roomid, players[1], addr, gameid, gameData.rule or "")
            if shortRoomid then
                break
            end
        end

        if not shortRoomid or shortRoomid == 0 then
            log.error("createPrivateShortRommid error")
            return
        end
    end

    -- 创建新的房间服务
    local gameRoom = skynet.newservice(name)
    local roomData = {
        gameid = gameid, 
        players = players, 
        gameData = gameData, 
        roomid = roomid, 
        addr = addr, 
        gameManager = skynet.self(),
        roomType = roomType,
        shortRoomid = shortRoomid,
    }
    
    -- 初始化房间服务
    skynet.call(gameRoom, "lua", "start", roomData)
    -- 保存房间信息
    if not allGames[gameid] then
        allGames[gameid] = {}
    end
    allGames[gameid][roomid] = gameRoom
    
    return roomid,addr,shortRoomid
end

--[[
创建匹配游戏房间
@param gameid 游戏ID
@param players 玩家列表
@param gameData 游戏数据
@return roomid 房间ID, addr 服务地址
]]
function CMD.createMatchGameRoom(gameid, players, gameData)
    return createGameRoom(gConfig.ROOM_TYPE.MATCH, gameid, players, gameData)
end

--[[
创建私人游戏房间
@param gameid 游戏ID
@param players 玩家列表
@param gameData 游戏数据
@return roomid 房间ID, addr 服务地址
]]
function CMD.createPrivateGameRoom(gameid, players, gameData)
    return createGameRoom(gConfig.ROOM_TYPE.PRIVATE, gameid, players, gameData)
end

--[[
销毁游戏房间
@param gameid 游戏ID
@param roomid 房间ID
@return 成功返回true，失败返回false
]]
function CMD.destroyGame(gameid, roomid)
    local b, room = checkHaveRoom(gameid, roomid)
    if not b or not room then
        log.error("game not found %s %s", gameid, roomid)
        return false
    end
    allGames[gameid][roomid] = nil
    skynet.send(room, "lua", "stop")
    return true
end

--[[
检查房间是否存在(对外接口)
@param gameid 游戏ID
@param roomid 房间ID
@return 存在返回true，不存在返回false
]]
function CMD.checkHaveRoom(gameid,roomid)
    local b, room = checkHaveRoom(gameid, roomid)
    return b
end

--[[
获取游戏房间服务地址
@param gameid 游戏ID
@param roomid 房间ID
@return 房间服务地址，不存在返回nil
]]
function CMD.getGame(gameid,roomid)
    local b,room = checkHaveRoom(gameid, roomid)
    return room
end

--[[
玩家连接游戏房间
@param userid 用户ID
@param gameid 游戏ID
@param roomid 房间ID
@param client_fd 客户端文件描述符
@return 连接结果
]]
function CMD.connectGame(userid,gameid,roomid,client_fd) 
    log.info("connectGame %d %d %d %d", gameid, roomid, userid, client_fd)
    local b, room = checkHaveRoom(gameid, roomid)
    if not b or not room then
        log.error("room not found %s %s", gameid, roomid)
        return
    end
    return skynet.call(room, "lua", "connectGame", userid, client_fd)
end

--[[
Skynet服务启动入口
注册服务、设置消息分发、初始化
]]
skynet.start(function()
    -- 设置Lua消息分发处理
    skynet.dispatch("lua", function(session, source, cmd, ...)
        log.info("dispatch %s %s", cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)
    addr = skynet.getenv("clusterName")
    -- 注册服务名称
    skynet.register(CONFIG.SVR_NAME.GAMES)
    -- 启动服务
    start()
    svrDB = skynet.localname(CONFIG.SVR_NAME.DB)
end)