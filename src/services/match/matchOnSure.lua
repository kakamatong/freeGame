local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local gConfig = CONFIG
local waitingOnSure = {}
local onSureIndex = 1
local onSureLimitTime = 5
local matchOnSure = {}

local sprotoloader = require "sprotoloader"
local host = sprotoloader.load(1):host "package"
local send_request = host:attach(sprotoloader.load(2))

local function sendSvrMsg(userid, typeName, data)
	local pack = send_request('svrMsg', {type = typeName, data = cjson.encode(data)}, 1)
    local gate = skynet.localname(".wsGateserver")
    if not gate then
        return
    end
    skynet.send(gate, "lua", "sendSvrMsg", userid, pack)
end

local function setUserStatus(userid, status, gameid, roomid)
    local svrUser = skynet.localname(".user")
    if not svrUser then
        return
    end
    skynet.send(svrUser, "lua", "svrCall" , "user", "setUserStatus", userid, status, gameid, roomid)
end

-- 创建游戏
local function createGame(gameid, playerids, gameData)
    local gameManager = skynet.localname(".gameManager")
    local roomid = skynet.call(gameManager, "lua", "createGame", gameid, playerids, gameData)
    return roomid
end

local function returnRobot( userids)
    local robotManager = skynet.localname(".robotManager")
    if not robotManager then
        return nil
    end
    skynet.send(robotManager, "lua", "returnRobots", userids)
end

local function isRobot(userid, robots)
    for i, v in ipairs(robots) do
        if v == userid then
            return true
        end
    end
    return false
end

local function createOnSureItem(gameid, queueid, playerids, data)
    local readys = {}
    if data.robots then
        readys = data.robots
    end
    local timeNow = os.time()
    onSureIndex = onSureIndex + 1
    local item = {
        gameid = gameid,
        queueid = queueid,
        playerids = playerids,
        data = data,
        readys = readys,
        cancels = {},
        createTime = timeNow,
        endTime = timeNow + onSureLimitTime,
        id = onSureIndex
    }
    table.insert(waitingOnSure, item)
    return item
end

local function destroyOnSureItem(index, msg)
    local item = waitingOnSure[index]
    table.remove(waitingOnSure, index)

    for _, y in ipairs(item.playerids) do
        --setUserStatus(v, gConfig.USER_STATUS.MATCHING, 0, 0)
        if item.data.robots and isRobot(y, item.data.robots) then
            --setUserStatus(y, gConfig.USER_STATUS.MATCHING, 0, 0)
        else
            sendSvrMsg(y, "matchOnSureFail", {code = 0, msg = msg})
        end
    end
    if item.data.robots then
        returnRobot(item.data.robots)
    end
end

local function onSureSuccess(item)
    local roomid = createGame(item.gameid, item.playerids, item.data)
    if roomid then
        for _, v in ipairs(item.playerids) do
            setUserStatus(v, gConfig.USER_STATUS.PLAYING, item.gameid, roomid)
            if item.data.robots and isRobot(v, item.data.robots) then
            else
                sendSvrMsg(v, "gameRoomReady", {roomid = roomid, gameid = item.gameid})
            end
        end
    end
end

local function getOnSureItem(id)
    for i, v in ipairs(waitingOnSure) do
        if v.id == id then
            return i,v
        end
    end
end

-----------------------------------------------------------------------------------
function matchOnSure.checkOnSure()
    local timeNow = os.time()
    for i, v in ipairs(waitingOnSure) do
        if timeNow > v.endTime then
            destroyOnSureItem(i, "游戏等待确认超时")
            i = i - 1
        end
    end
end

function matchOnSure.onSure(userid, id, sure)
    local index,item = getOnSureItem(id)
    if not item then
        return {code = 0, msg = "游戏不存在"}
    end
    if item.playerids[1] ~= userid then
        return {code = 0, msg = "游戏不匹配"}
    end
    if sure then
        --matchSuccess(item.gameid, item.queueid, item.playerids[1], item.playerids[2])
        table.insert(item.readys, userid)
        for i, v in ipairs(item.playerids) do
            sendSvrMsg(v, "matchOnSure", item)
        end
        if #item.readys == #item.playerids then
            --matchSuccess(item.gameid, item.queueid, item.playerids[1], item.playerids[2])
            table.remove(waitingOnSure, index)
            onSureSuccess(item)
        end
    else
        log.info("match fail %d", userid)
        destroyOnSureItem(index, "玩家拒绝")
        return {code = 1, msg = "拒绝成功"}
    end
end

-- 开始超时
function matchOnSure.startOnSure(gameid, queueid, playerids, data)
    local item = createOnSureItem(gameid, queueid, playerids, data)
    for i, v in ipairs(playerids) do
        -- todo: 机器人
        if data.robots and isRobot(v, data.robots) then
            
        else
            sendSvrMsg(v, "matchOnSure", item)
        end
    end
end

return matchOnSure