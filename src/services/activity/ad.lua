local ad = {}
local cjson = require "cjson"
local tools = require "activity.tools"

-- 广告奖励配置（可配置化）
local adConfig = {
    maxDailyRewardCount = 5,  -- 每天最大领取次数
    rewards = {
        {
            richTypes = {CONFIG.RICH_TYPE.SILVER_COIN},
            richNums = {10}
        }
    }
}

-- Redis键名配置
local REDIS_KEY_AD_PREFIX = "adReward:"  -- 广告奖励状态键前缀



-- 获取用户广告奖励数据
local function getUserAdData(userid)
    local key = REDIS_KEY_AD_PREFIX .. userid
    local data = tools.callRedis("get", key)
    if not data then
        -- 初始化用户数据
        local newData = {
            lastRewardTime = 0,
            dailyRewardCount = 0,
            rewardDate = 0  -- 最后领取日期（YYYYMMDD格式）
        }
        return newData
    end
    return cjson.decode(data)
end

-- 设置用户广告奖励数据
local function setUserAdData(userid, data, expire)
    local key = REDIS_KEY_AD_PREFIX .. userid
    tools.callRedis("set", key, cjson.encode(data), expire or 86400)  -- 默认24小时过期
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

-- 获取广告配置
local function getAdConfig()
    return adConfig
end

-- 获取广告活动配置接口
function ad.getAdInfo(userid, args)
    local resp = {}
    local userData = getUserAdData(userid)
    local config = getAdConfig()
    
    -- 检查是否需要重置每日计数
    checkAndResetDailyCount(userData)
    
    resp.maxDailyRewardCount = config.maxDailyRewardCount
    resp.currentRewardCount = userData.dailyRewardCount
    resp.rewards = config.rewards
    resp.canReward = userData.dailyRewardCount < config.maxDailyRewardCount
    
    -- 更新用户数据（主要是可能重置后的数据）
    setUserAdData(userid, userData)
    
    return tools.result(resp)
end

-- 领取广告奖励接口
function ad.getAdReward(userid, args)
    local resp = {}
    local userData = getUserAdData(userid)
    local config = getAdConfig()
    
    -- 检查是否需要重置每日计数
    checkAndResetDailyCount(userData)
    
    -- 检查是否还能领取奖励
    if userData.dailyRewardCount >= config.maxDailyRewardCount then
        return tools.result({error = "今日奖励已领完"})
    end
    
    -- Redis锁防止并发领取
    local lockKey = "adLock:" .. userid
    local lockValue = os.time()
    local lockExpire = 2000  -- 2秒锁
    local lock = tools.callRedis("lock", lockKey, lockValue, lockExpire)
    if not lock then
        return tools.result({error = "操作频繁，请稍后再试"})
    end
    
    -- 再次检查（双重检查）
    userData = getUserAdData(userid)
    checkAndResetDailyCount(userData)
    if userData.dailyRewardCount >= config.maxDailyRewardCount then
        tools.callRedis("unlock", lockKey)
        return tools.result({error = "今日奖励已领完"})
    end
    
    -- 更新用户数据
    userData.dailyRewardCount = userData.dailyRewardCount + 1
    userData.lastRewardTime = os.time()
    local todayDate = tonumber(os.date("%Y%m%d", os.time()))
    userData.rewardDate = todayDate
    
    -- 保存到Redis，设置24小时过期
    setUserAdData(userid, userData, 86400)
    
    -- 发放奖励（参考daySignIn的实现）
    local rewardData = config.rewards[1]  -- 取第一个奖励配置
    local richTypes = rewardData.richTypes
    local richNums = rewardData.richNums
    
    -- 发奖
    for i = 1, #richTypes do
        local res = tools.callMysql("addUserRiches", userid, richTypes[i], richNums[i])
        if not res then
            tools.callRedis("unlock", lockKey)
            return tools.result({error = "发奖失败"})
        end
    end
    
    -- 释放锁
    tools.callRedis("unlock", lockKey)
    
    -- 发送奖励通知
    local strData = cjson.encode(rewardData)
    local id = call(CONFIG.CLUSTER_SVR_NAME.USER, "awardNotice", userid, strData)
    
    -- 返回结果
    local res = {
        noticeid = id,
        reward = rewardData,
        currentRewardCount = userData.dailyRewardCount,
        maxDailyRewardCount = config.maxDailyRewardCount
    }
    
    return tools.result(res)
end



return ad