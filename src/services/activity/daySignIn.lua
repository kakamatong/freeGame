local daySignIn = {}
local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local oneHour = 3600
local oneDay = oneHour * 24
local maxSignInIndex = 7
local name = "daySignIn"

local signInConfig = {
    -- 第一天
    {
        richTypes = {2},
        richNums = {10000}
    },
    -- 第二天
    {
        richTypes = {2},
        richNums = {20000}
    },
    -- 第三天
    {
        richTypes = {2},
        richNums = {30000}
    },
    -- 第四天
    {
        richTypes = {2},
        richNums = {40000}
    },
    -- 第五天
    {
        richTypes = {2},
        richNums = {50000}
    },
    -- 第六天
    {
        richTypes = {2},
        richNums = {60000}
    },
    -- 第七天
    {
        richTypes = {2},
        richNums = {70000}
    },
}

local REIDS_KEY_FIRST_DAY = "signInFirstDay"
local REIDS_FIELD_FIRST_DAY = "firstDay:%d"

local function result(info)
    local msg = {}
    if info then
        msg = info
    end
    return {code = 1, result = cjson.encode(msg)}
end

local function getDB()
    local dbserver = skynet.localname(".dbserver")
	assert(dbserver, "dbserver not started")
	return dbserver
end

local function callRedis(func,...)
    local db = getDB()
    return skynet.call(db, "lua", "funcRedis", func, ...)
end

local function callMysql(func,...)
    local db = getDB()
    return skynet.call(db, "lua", "func", func, ...)
end

-- 获取当日0点的时间戳
local function getTimeNow()
    local time = os.time()
    local year = os.date("%Y", time)
    local month = os.date("%m", time)
    local day = os.date("%d", time)
    return os.time({year = year, month = month, day = day, hour = 0, minute = 0, second = 0})
end

local function getSignInData(userid)
    local db = getDB()
    local field = string.format(REIDS_FIELD_FIRST_DAY, userid)
    local data = callRedis("get", field)
    if not data then
        return nil
    end
    return cjson.decode(data)
end

local function setSignInData(userid, data, expire)
    local db = getDB()
    local field = string.format(REIDS_FIELD_FIRST_DAY, userid)
    callRedis("set", field, cjson.encode(data), expire)
end

local function getSignInIndex(timeFirst, timeNow)
    local timeDiff = timeNow - timeFirst
    local index = math.floor(timeDiff / oneDay) + 1
    return index
end

local function getUserSignInData(userid)
    local signInData = getSignInData(userid)
    local timeNow = getTimeNow()
    local signInIndex = 1
    if not signInData then
        local data = {
            timeFirst = timeNow,
            status = {0,0,0,0,0,0,0}
        }
        signInData = data
        setSignInData(userid, data, oneDay * 8)
    else
        local firstDay = signInData.timeFirst
        signInIndex = getSignInIndex(firstDay, timeNow)
    end

    if signInIndex > maxSignInIndex then
        signInIndex = 1
        local data = {
            timeFirst = timeNow,
            status = {0,0,0,0,0,0,0}
        }
        signInData = data
        setSignInData(userid, data, oneDay * 8)
    end

    return signInIndex, signInData
end

function daySignIn.getSignInInfo(args)
    local userid = args.userid
    local resp = {}
    local signInIndex, signInData = getUserSignInData(userid)
    
    resp.signInIndex = signInIndex
    resp.signInConfig = signInConfig
    resp.signStatus = signInData.status
    return result(resp)
end

function daySignIn.signIn(args)
    local userid = args.userid
    local resp = {}
    local signInIndex, signInData = getUserSignInData(userid)
    if signInData.status[signInIndex] > 0 then
        return result({error = "已经签到过了"})
    else
        -- redis 锁
        local lockKey = string.format("signInLock:%d", userid)
        local lockValue = os.time()
        local lockExpire = 2000
        local lock = callRedis("lock", lockKey, lockValue, lockExpire)
        if not lock then
            return result({error = "签到失败"})
        end

        -- 更新签到状态
        signInData.status[signInIndex] = 1
        setSignInData(userid, signInData, oneDay * (8 - signInIndex))
        -- 发奖
        local richType = signInConfig[signInIndex].richTypes[1]
        local richNum = signInConfig[signInIndex].richNums[1]
        local res = callMysql("addUserRiches", userid, richType, richNum)
        if not res then
            return result({error = "发奖失败"})
        end
        callRedis("unlock", lockKey)
        return result(signInConfig[signInIndex])
        -- 更新财富通知
    end
end

return daySignIn