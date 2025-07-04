local daySignIn = {}
local skynet = require "skynet"
local log = require "log"
local cjson = require "cjson"
local oneHour = 3600
local oneDay = oneHour * 24
local maxSignInIndex = 7
local name = "daySignIn"
local tools = require "activity.tools"

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

local STATUS_SIGN = {
    NOT_SIGNIN = 0,
    SIGNIN = 1,
    FILL_SIGNIN = 2
}

local REIDS_KEY_FIRST_DAY = "signInFirstDay"
local REIDS_FIELD_FIRST_DAY = "firstDay:%d"

-- 获取当日0点的时间戳
local function getTimeNow()
    local time = os.time()
    local year = os.date("%Y", time)
    local month = os.date("%m", time)
    local day = os.date("%d", time)
    return os.time({year = year, month = month, day = day, hour = 0, minute = 0, second = 0})
end

-- 获取签到数据
local function getSignInData(userid)
    local field = string.format(REIDS_FIELD_FIRST_DAY, userid)
    local data = tools.callRedis("get", field)
    if not data then
        return nil
    end
    return cjson.decode(data)
end

-- 设置签到数据
local function setSignInData(userid, data, expire)
    local field = string.format(REIDS_FIELD_FIRST_DAY, userid)
    tools.callRedis("set", field, cjson.encode(data), expire)
end

-- 获取签到索引
local function getSignInIndex(timeFirst, timeNow)
    local timeDiff = timeNow - timeFirst
    local index = math.floor(timeDiff / oneDay) + 1
    return index
end

-- 获取用户签到数据
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

-- 获取签到信息
function daySignIn.getSignInInfo(userid, args)
    local resp = {}
    local signInIndex, signInData = getUserSignInData(userid)
    
    resp.signInIndex = signInIndex
    resp.signInConfig = signInConfig
    resp.signStatus = signInData.status
    return UTILS.result(resp)
end

-- 签到
function daySignIn.signIn(userid, args)
    local resp = {}
    local signInIndex, signInData = getUserSignInData(userid)
    if signInData.status[signInIndex] > STATUS_SIGN.NOT_SIGNIN then
        return UTILS.result({error = "已经签到过了"})
    else
        -- redis 锁
        local lockKey = string.format("signInLock:%d", userid)
        local lockValue = os.time()
        local lockExpire = 2000
        local lock = tools.callRedis("lock", lockKey, lockValue, lockExpire)
        if not lock then
            return UTILS.result({error = "签到失败"})
        end

        -- 更新签到状态
        signInData.status[signInIndex] = STATUS_SIGN.SIGNIN
        setSignInData(userid, signInData, oneDay * (8 - signInIndex))
        -- 发奖
        local richTypes = signInConfig[signInIndex].richTypes
        local richNums = signInConfig[signInIndex].richNums
        local allRichNums = {}
        for i = 1, #richTypes do
            local res = tools.callMysql("addUserRiches", userid, richTypes[i], richNums[i])
            if not res then
                return UTILS.result({error = "发奖失败"})
            end

            local all = tools.callMysql("getUserRichesByType", userid, richTypes[i])
            if not res then
                table.insert(allRichNums, 0)
            else
                table.insert(allRichNums, all.richNums)
            end
        end
        tools.callRedis("unlock", lockKey)
        -- 更新财富通知
        tools.reportAward(userid, richTypes, richNums, allRichNums)
        return UTILS.result(signInConfig[signInIndex])
    end
end

-- 补签
function daySignIn.fillSignIn(userid, args)
    local resp = {}
    local fillIndex = args.index
    local signInIndex, signInData = getUserSignInData(userid)
    if fillIndex and fillIndex >= signInIndex then
        return UTILS.result({error = "参数错误"})
    end
    if signInData.status[fillIndex] > STATUS_SIGN.NOT_SIGNIN then
        return UTILS.result({error = "已经签到过了"})
    else
         -- redis 锁
         local lockKey = string.format("signInLock:%d", userid)
         local lockValue = os.time()
         local lockExpire = 2000
         local lock = tools.callRedis("lock", lockKey, lockValue, lockExpire)
         if not lock then
             return UTILS.result({error = "签到失败"})
         end
 
         -- 更新签到状态
         signInData.status[fillIndex] = STATUS_SIGN.FILL_SIGNIN
         setSignInData(userid, signInData, oneDay * (8 - fillIndex))
         -- 发奖
         local richTypes = signInConfig[fillIndex].richTypes
         local richNums = signInConfig[fillIndex].richNums
         local allRichNums = {}
         for i = 1, #richTypes do
             local res = tools.callMysql("addUserRiches", userid, richTypes[i], richNums[i])
             if not res then
                 return UTILS.result({error = "发奖失败"})
             end

             
            local all = tools.callMysql("getUserRichesByType", userid, richTypes[i])
            if not res then
                table.insert(allRichNums, 0)
            else
                table.insert(allRichNums, all.richNums)
            end
         end
         tools.callRedis("unlock", lockKey)
         -- 更新财富通知
         tools.reportAward(userid, richTypes, richNums, allRichNums)
         return UTILS.result(signInConfig[fillIndex])
    end
end

return daySignIn