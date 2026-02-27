--[[
    matchConfig.lua
    匹配系统配置文件
    位置：services/match/ 目录下，与逻辑代码在一起
]]

local matchConfig = {}

-- 默认匹配配置
matchConfig.default = {
    mode = "fixed",           -- "fixed"(固定) | "dynamic"(动态)
    maxPlayers = 2,           -- 最大人数
    minPlayers = 2,           -- 最小人数
    rateDiff = 500,           -- 战力差阈值
    robotAfterFails = 1,      -- 失败多少次后匹配机器人
    confirmTime = 5,          -- 确认等待时间（秒）
}

-- 游戏匹配配置
matchConfig.games = {
    [10001] = {
        queueNum = 4,
        -- 所有队列使用默认配置
    },
    
    [10002] = {
        queueNum = 4,
        
        [1] = {                   -- 动态匹配（2-4人）
            mode = "dynamic",
            maxPlayers = 5,
            minPlayers = 2,
            rateDiff = 1000,
            robotAfterFails = 3,
        },
        
        [2] = {                   -- 固定2人（严格匹配）
            mode = "dynamic",
            maxPlayers = 5,
            minPlayers = 2,
            rateDiff = 300,
        },
        
        -- queueid=3,4 使用默认配置
    },
}

-- 机器人配置
matchConfig.robot = {
    enabled = true,
    minWaitTime = 30,
    fillToMax = true,         -- 动态模式下是否补满到maxPlayers
}

-- 获取配置（供match.lua和matchOnSure.lua调用）
function matchConfig.get(gameid, queueid)
    local gameCfg = matchConfig.games[gameid]
    if not gameCfg then
        return matchConfig.default
    end
    
    local queueCfg = gameCfg[queueid]
    if queueCfg then
        local result = {}
        for k, v in pairs(matchConfig.default) do
            result[k] = v
        end
        for k, v in pairs(queueCfg) do
            result[k] = v
        end
        return result
    end
    
    return matchConfig.default
end

return matchConfig
