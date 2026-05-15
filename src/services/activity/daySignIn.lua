local daySignIn = {}
local cjson = require "cjson"
local oneHour = 3600
local oneDay = oneHour * 24
local tools = require "activity.tools"

-- 多份签到配置，key 为配置ID（客户端通过 args.cfgId 传入）
local signInConfigs = {
    -- 默认配置
    [1] = {
        maxSignInIndex = 7,
        awards = {
            -- 第一天
            { richTypes = {CONFIG.RICH_TYPE.SILVER_COIN}, richNums = {5},  richNums2 = {10} },
            -- 第二天
            { richTypes = {CONFIG.RICH_TYPE.SILVER_COIN}, richNums = {10}, richNums2 = {20} },
            -- 第三天
            { richTypes = {CONFIG.RICH_TYPE.SILVER_COIN}, richNums = {15}, richNums2 = {30} },
            -- 第四天
            { richTypes = {CONFIG.RICH_TYPE.SILVER_COIN}, richNums = {20}, richNums2 = {40} },
            -- 第五天
            { richTypes = {CONFIG.RICH_TYPE.SILVER_COIN}, richNums = {25}, richNums2 = {50} },
            -- 第六天
            { richTypes = {CONFIG.RICH_TYPE.SILVER_COIN}, richNums = {30}, richNums2 = {60} },
            -- 第七天
            { richTypes = {CONFIG.RICH_TYPE.SILVER_COIN}, richNums = {50}, richNums2 = {100} },
        },
    },
    -- 在此追加更多配置，如 [2] = { maxSignInIndex = 7, awards = { ... } }
    [2] = {
        maxSignInIndex = 7,
        awards = {
            -- 第一天
            { richTypes = {CONFIG.RICH_TYPE.AUTO_REMOVE}, richNums = {2},  richNums2 = {4} },
            -- 第二天
            { richTypes = {CONFIG.RICH_TYPE.AUTO_REMOVE}, richNums = {3}, richNums2 = {6} },
            -- 第三天
            { richTypes = {CONFIG.RICH_TYPE.AUTO_REMOVE}, richNums = {4}, richNums2 = {8} },
            -- 第四天
            { richTypes = {CONFIG.RICH_TYPE.AUTO_REMOVE}, richNums = {5}, richNums2 = {10} },
            -- 第五天
            { richTypes = {CONFIG.RICH_TYPE.AUTO_REMOVE}, richNums = {6}, richNums2 = {12} },
            -- 第六天
            { richTypes = {CONFIG.RICH_TYPE.AUTO_REMOVE,CONFIG.RICH_TYPE.UPSET}, richNums = {6,2}, richNums2 = {12,4} },
            -- 第七天
            { richTypes = {CONFIG.RICH_TYPE.AUTO_REMOVE,CONFIG.RICH_TYPE.UPSET}, richNums = {6,3}, richNums2 = {12,6} },
        },
    },
}

-- 获取指定配置（不存在则返回默认配置 #1）
local function getSignInCfg(cfgId)
    return signInConfigs[cfgId or 1] or signInConfigs[1]
end

local STATUS_SIGN = {
    NOT_SIGNIN = 0,
    SIGNIN = 1,
    FILL_SIGNIN = 2
}

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
local function getUserSignInData(userid, cfgId)
    local cfg = getSignInCfg(cfgId)
    local maxSignInIndex = cfg.maxSignInIndex
    local signInData = getSignInData(userid)
    local timeNow = getTimeNow()
    local signInIndex = 1
    if not signInData then
        local status = {}
        for i = 1, maxSignInIndex do status[i] = 0 end
        local data = {
            timeFirst = timeNow,
            status = status
        }
        signInData = data
        setSignInData(userid, data, oneDay * (maxSignInIndex + 1))
    else
        local firstDay = signInData.timeFirst
        signInIndex = getSignInIndex(firstDay, timeNow)
    end

    if signInIndex > maxSignInIndex then
        signInIndex = 1
        local status = {}
        for i = 1, maxSignInIndex do status[i] = 0 end
        local data = {
            timeFirst = timeNow,
            status = status
        }
        signInData = data
        setSignInData(userid, data, oneDay * (maxSignInIndex + 1))
    end

    return signInIndex, signInData, cfg
end

-- 获取签到信息
function daySignIn.getSignInInfo(userid, args)
    local cfgId = args and args.cfgId or 1
    local resp = {}
    local signInIndex, signInData, cfg = getUserSignInData(userid, cfgId)
    
    resp.signInIndex = signInIndex
    resp.signInConfig = cfg.awards
    resp.signStatus = signInData.status
    return tools.result(resp)
end

-- 签到
function daySignIn.signIn(userid, args)
    local cfgId = args and args.cfgId or 1
    local mult = args and args.mult
    local resp = {}
    local signInIndex, signInData, cfg= getUserSignInData(userid, cfgId)
    local maxSignInIndex = cfg.maxSignInIndex
    if signInData.status[signInIndex] > STATUS_SIGN.NOT_SIGNIN then
        return tools.result({error = "已经签到过了"})
    else
        -- redis 锁
        local lockKey = string.format("signInLock:%d:%d", cfgId, userid)
        local lockValue = os.time()
        local lockExpire = 2000
        local lock = tools.callRedis("lock", lockKey, lockValue, lockExpire)
        if not lock then
            return tools.result({error = "签到失败"})
        end

        -- 更新签到状态
        signInData.status[signInIndex] = STATUS_SIGN.SIGNIN
        setSignInData(userid, signInData, oneDay * (maxSignInIndex + 1 - signInIndex))
        -- 发奖
        local awardData = cfg.awards[signInIndex]
        local awards = awardData.richNums
        -- 翻倍，一般是看广告
        if mult and mult == 1 then
            awards = awardData.richNums2
        end
        local richTypes = awardData.richTypes
        local richNums = awards
        for i = 1, #richTypes do
            local res = tools.callMysql("addUserRiches", userid, richTypes[i], richNums[i])
            if not res then
                return tools.result({error = "发奖失败"})
            end
        end
        tools.callRedis("unlock", lockKey)
        local strData = cjson.encode(awardData)
        local id = call(CONFIG.CLUSTER_SVR_NAME.USER, "awardNotice", userid, strData)
        local res = {
            noticeid = id,
            awards = awardData,
            status = signInData.status
        }
        return tools.result(res)
    end
end

-- 补签
function daySignIn.fillSignIn(userid, args)
    local cfgId = args and args.cfgId or 1
    local resp = {}
    local fillIndex = args and args.index
    local signInIndex, signInData, cfg = getUserSignInData(userid, cfgId)
    local maxSignInIndex = cfg.maxSignInIndex
    if fillIndex and fillIndex >= signInIndex then
        return tools.result({error = "参数错误"})
    end
    if signInData.status[fillIndex] > STATUS_SIGN.NOT_SIGNIN then
        return tools.result({error = "已经签到过了"})
    else
        -- redis 锁
        local lockKey = string.format("signInLock:%d:%d", cfgId, userid)
        local lockValue = os.time()
        local lockExpire = 2000
        local lock = tools.callRedis("lock", lockKey, lockValue, lockExpire)
        if not lock then
            return tools.result({error = "签到失败"})
        end

        -- 更新签到状态
        signInData.status[fillIndex] = STATUS_SIGN.FILL_SIGNIN
        setSignInData(userid, signInData, oneDay * (maxSignInIndex + 1 - fillIndex))
        -- 发奖
        local awardData = cfg.awards[fillIndex]
        local richTypes = awardData.richTypes
        local richNums = awardData.richNums
        -- todo: 优化，合并成一条sql
        for i = 1, #richTypes do
            local res = tools.callMysql("addUserRiches", userid, richTypes[i], richNums[i])
            if not res then
                return tools.result({error = "发奖失败"})
            end
        end
        tools.callRedis("unlock", lockKey)
        local strData = cjson.encode(awardData)
        local id = call(CONFIG.CLUSTER_SVR_NAME.USER, "awardNotice", userid, strData)
        local res = {
            noticeid = id,
            awards = awardData,
            status = signInData.status
        }
         return tools.result(res)
    end
end

return daySignIn