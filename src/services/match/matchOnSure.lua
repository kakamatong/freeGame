local skynet = require "skynet"
local log = require "log"
local gConfig = CONFIG
local waitingOnSure = {}
local onSureIndex = 1
local onSureLimitTime = 5
local matchOnSure = {}
local svrRobot = gConfig.CLUSTER_SVR_NAME.ROBOT
local svrUser = gConfig.CLUSTER_SVR_NAME.USER
local svrGate = gConfig.CLUSTER_SVR_NAME.GATE
local svrGame = gConfig.CLUSTER_SVR_NAME.GAME
local sprotoloader = require "sprotoloader"
local host = sprotoloader.load(1):host "package"
local send_request = host:attach(sprotoloader.load(2))

local function sendSvrMsg(userid,xyName, data)
	local pack = send_request(xyName, data, 1)
    call(svrGate, "sendSvrMsg", userid, pack)
end

local function setUserStatus(userid, status, gameid, roomid)
    send(svrUser, "setUserStatus", userid, status, gameid, roomid)
end

-- 创建游戏
local function createGame(gameid, playerids, gameData)
    local roomid = call(svrGame, "createGame", gameid, playerids, gameData)
    return roomid
end

local function returnRobot( userids)
    send(svrRobot, "returnRobots", userids)
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
        for _,v in pairs(data.robots) do
            table.insert(readys, v)
        end
        --readys = data.robots
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

local function onSureSuccess(index, item)
    table.remove(waitingOnSure, index)
    local roomid = createGame(item.gameid, item.playerids, item.data)
    if roomid then
        for _, v in ipairs(item.playerids) do
            setUserStatus(v, gConfig.USER_STATUS.GAMEING, item.gameid, roomid)
            if item.data.robots and isRobot(v, item.data.robots) then
            else
                sendSvrMsg(v, "gameRoomReady", {roomid = roomid, gameid = item.gameid})
            end
        end
    end

    return roomid
end

local function getOnSureItem(id)
    for i, v in ipairs(waitingOnSure) do
        if v.id == id then
            return i,v
        end
    end
end

local function sendMatchOnSure(item)
    if not item or not item.playerids then
        return
    end

    local robots = item.data.robots
    for _,v in pairs(item.playerids) do
        if robots and isRobot(v, robots) then
            
        else
            sendSvrMsg(v, "matchOnSure", item)
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
    -- if item.playerids[1] ~= userid then
    --     return {code = 0, msg = "游戏不匹配"}
    -- end
    for _, value in pairs(item.readys) do
        if value == userid then
            log.warn("matchOnSure onSure %d %d", userid, id)
            return {code = 0, msg = "已同意"}
        end
    end
    if sure then
        --matchSuccess(item.gameid, item.queueid, item.playerids[1], item.playerids[2])
        table.insert(item.readys, userid)
        sendMatchOnSure(item)
        if #item.readys == #item.playerids then
            --matchSuccess(item.gameid, item.queueid, item.playerids[1], item.playerids[2])
            local roomid = onSureSuccess(index, item)
            if roomid then
                return {code = 1, msg = "匹配成功", roomid = roomid, gameid = item.gameid}
            else
                return {code = 0, msg = "建房失败", roomid = roomid, gameid = item.gameid}
            end
            
        end
    else
        log.info("match fail %d", userid)
        destroyOnSureItem(index, "玩家拒绝")
        return {code = 0, msg = "拒绝成功"}
    end
end

-- 开始超时
function matchOnSure.startOnSure(gameid, queueid, playerids, data)
    log.info("matchOnSure startOnSure %d %d %s", gameid, queueid, UTILS.tableToString(data))
    local item = createOnSureItem(gameid, queueid, playerids, data)
    if #item.playerids == #item.readys then
        local index,item1 = getOnSureItem(item.id)
        onSureSuccess(index, item1)
    else
        sendMatchOnSure(item)
    end
end

return matchOnSure