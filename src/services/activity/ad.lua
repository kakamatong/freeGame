local ad = {}
local cjson = require "cjson"
local tools = require "activity.tools"

-- 多份广告奖励配置，key 为配置ID（客户端通过 args.cfgId 传入）
local adConfigs = {
    -- 默认配置
    [1] = {
        maxDailyRewardCount = 5,  -- 每天最大领取次数
        rewards = {
            {
                richTypes = {CONFIG.RICH_TYPE.SILVER_COIN},
                richNums = {10}
            }
        }
    },
    -- 在此追加更多配置，如 [2] = { maxDailyRewardCount = 3, rewards = { ... } }
}

-- 获取指定配置（不存在则返回默认配置 #1）
local function getAdCfg(cfgId)
    return adConfigs[cfgId or 1] or adConfigs[1]
end

-- Redis键名配置（不区分cfgId，兼容线上）
local REDIS_KEY_AD_PREFIX = "adReward:"

-- 获取用户广告奖励数据
local function getUserAdData(userid)
    local key = REDIS_KEY_AD_PREFIX .. userid
    local data = tools.callRedis("get", key)
    if not data then
        local newData = {
            lastRewardTime = 0,
            dailyRewardCount = 0,
            rewardDate = 0
        }
        return newData
    end
    return cjson.decode(data)
end

-- 设置用户广告奖励数据
local function setUserAdData(userid, data, expire)
    local key = REDIS_KEY_AD_PREFIX .. userid
    tools.callRedis("set", key, cjson.encode(data), expire or 86400)
end

-- 检查是否需要重置每日计数（跨天重置）
local function checkAndResetDailyCount(data)
    local now = os.time()
    local todayDate = tonumber(os.date("%Y%m%d", now))
    
    if data.rewardDate < todayDate then
        data.dailyRewardCount = 0
        data.rewardDate = todayDate
    end
end

-- 获取广告活动配置接口
function ad.getAdInfo(userid, args)
    local cfgId = args and args.cfgId or 1
    local cfg = getAdCfg(cfgId)
    local resp = {}
    local userData = getUserAdData(userid)
    
    checkAndResetDailyCount(userData)
    
    resp.maxDailyRewardCount = cfg.maxDailyRewardCount
    resp.currentRewardCount = userData.dailyRewardCount
    resp.rewards = cfg.rewards
    resp.canReward = userData.dailyRewardCount < cfg.maxDailyRewardCount
    
    setUserAdData(userid, userData)
    
    return tools.result(resp)
end

-- 领取广告奖励接口
function ad.getAdReward(userid, args)
    local cfgId = args and args.cfgId or 1
    local cfg = getAdCfg(cfgId)
    local resp = {}
    local userData = getUserAdData(userid)
    
    checkAndResetDailyCount(userData)
    
    if userData.dailyRewardCount >= cfg.maxDailyRewardCount then
        return tools.result({error = "今日奖励已领完"})
    end
    
    -- Redis锁（区分cfgId）
    local lockKey = string.format("adLock:%d:%d", cfgId, userid)
    local lockValue = os.time()
    local lockExpire = 2000
    local lock = tools.callRedis("lock", lockKey, lockValue, lockExpire)
    if not lock then
        return tools.result({error = "操作频繁，请稍后再试"})
    end
    
    -- 双重检查
    userData = getUserAdData(userid)
    checkAndResetDailyCount(userData)
    if userData.dailyRewardCount >= cfg.maxDailyRewardCount then
        tools.callRedis("unlock", lockKey)
        return tools.result({error = "今日奖励已领完"})
    end
    
    userData.dailyRewardCount = userData.dailyRewardCount + 1
    userData.lastRewardTime = os.time()
    local todayDate = tonumber(os.date("%Y%m%d", os.time()))
    userData.rewardDate = todayDate
    
    setUserAdData(userid, userData, 86400)
    
    local rewardData = cfg.rewards[1]
    local richTypes = rewardData.richTypes
    local richNums = rewardData.richNums
    
    for i = 1, #richTypes do
        local res = tools.callMysql("addUserRiches", userid, richTypes[i], richNums[i])
        if not res then
            tools.callRedis("unlock", lockKey)
            return tools.result({error = "发奖失败"})
        end
    end
    
    tools.callRedis("unlock", lockKey)
    
    local strData = cjson.encode(rewardData)
    local id = call(CONFIG.CLUSTER_SVR_NAME.USER, "awardNotice", userid, strData)
    
    local res = {
        noticeid = id,
        reward = rewardData,
        currentRewardCount = userData.dailyRewardCount,
        maxDailyRewardCount = cfg.maxDailyRewardCount
    }
    
    return tools.result(res)
end

return ad
