--[[
    questionSource.lua
    算24点(10003)出题来源策略：决定“本局走题库还是本地随机”，以及走题库时用哪个难度。
    规则来源（产品设定）：
      匹配房：10% 走题库，题库难度按权重 30/30/20/15/5
      私人房按难度等级（客户端上抛 key = difficulty）：
        0 随机：50% 本地随机 / 50% 题库，题库难度 1-5 均匀随机
        1 简单：纯本地随机，不走题库
        2 中等：走题库，难度 1-3 均匀随机
        3 困难：走题库，难度 3-5 均匀随机
    说明：本模块不依赖 skynet，可用 Lua 解释器离线单测；调用方（Room）负责实际取题与失败回退。
]]

local difficulty = require "games.10003.difficulty"

local source = {}

-- 私人房难度等级（与客户端 ctrl_difficulty 页面id一致）
source.PRIVATE_RANDOM = 0
source.PRIVATE_EASY = 1
source.PRIVATE_MEDIUM = 2
source.PRIVATE_HARD = 3

-- 匹配房：10% 题库 + 权重难度
source.MATCH_PLAN = { bankRate = 10, mode = "weighted" }

-- 私人房：按等级的出题来源计划（bankRate 为走题库的概率百分比）
source.PRIVATE_PLANS = {
    [source.PRIVATE_RANDOM] = { bankRate = 50, mode = "uniform", min = 1, max = 5 },
    [source.PRIVATE_EASY] = { bankRate = 0 },
    [source.PRIVATE_MEDIUM] = { bankRate = 100, mode = "uniform", min = 1, max = 3 },
    [source.PRIVATE_HARD] = { bankRate = 100, mode = "uniform", min = 3, max = 5 },
}

--[[
    规整私人房难度：非法值一律按“随机(0)”处理
    @param value any 客户端上抛的 difficulty
    @return number 0~3
]]
function source.normalizePrivateDifficulty(value)
    local id = tonumber(value)
    if not id or not source.PRIVATE_PLANS[id] then
        return source.PRIVATE_RANDOM
    end
    return id
end

--[[
    取出题来源计划
    @param isMatchRoom boolean 是否匹配房
    @param privateDifficulty any 私人房难度（匹配房忽略）
    @return table 计划 {bankRate, mode, min, max}
]]
function source.plan(isMatchRoom, privateDifficulty)
    if isMatchRoom then
        return source.MATCH_PLAN
    end
    return source.PRIVATE_PLANS[source.normalizePrivateDifficulty(privateDifficulty)]
end

--[[
    掷一次出题来源
    @param plan table 来源计划
    @return boolean 是否走题库
    @return number|nil 走题库时的难度id
]]
function source.roll(plan)
    local rate = plan.bankRate or 0
    if rate <= 0 then
        return false
    end
    if math.random(1, 100) > rate then
        return false
    end
    if plan.mode == "weighted" then
        return true, difficulty.roll()
    end
    return true, math.random(plan.min or 1, plan.max or 5)
end

return source
