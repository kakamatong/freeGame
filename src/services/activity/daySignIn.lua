local daySignIn = {}
local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local oneHour = 3600
local oneDay = oneHour * 24
local maxSignInIndex = 7

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
    local data = callRedis("hget", REIDS_KEY_FIRST_DAY, field)
    if not data then
        return nil
    end
    return cjson.decode(data)
end

local function setSignInData(userid, data)
    local db = getDB()
    local field = string.format(REIDS_FIELD_FIRST_DAY, userid)
    callRedis("hset", REIDS_KEY_FIRST_DAY, field, cjson.encode(data))
end

local function getSignInIndex(timeFirst, timeNow)
    local timeDiff = timeNow - timeFirst
    local index = math.floor(timeDiff / oneDay) + 1
    return index
end

function daySignIn.getSignInInfo(args)
    local userid = args.userid
    local resp = {}
    local timeNow = getTimeNow()
    local signInData = getSignInData(userid)
    local signInIndex = 1
    if not signInData then
        local data = {
            timeFirst = timeNow,
            status = {0,0,0,0,0,0,0}
        }
        signInData = data
        setSignInData(userid, data)
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
        setSignInData(userid, data)
    end

    resp.signInIndex = signInIndex
    resp.signInConfig = signInConfig
    resp.signStatus = signInData.status
    return result(resp)
end

function daySignIn.signIn(args)
    local userid = args.userid
    local resp = {}

    local firstDay = redis.call("HGET", REIDS_KEY_FIRST_DAY, userid)
    if not firstDay then
        firstDay = 0
    end
end

return daySignIn