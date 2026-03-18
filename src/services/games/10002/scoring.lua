local log = require "log"
local cjson = require "cjson"

local ScoringSystem = {}
ScoringSystem.__index = ScoringSystem

--[[
    创建计分系统实例
    @param config: table 配置参数
        - K_base: 基础K值（决定每局最大分数变化）
        - S_max: 高分阈值（超过此分数后K值开始减少）
        - initial_score: 初始分数
        - min_score: 最低分数
        - low_score_threshold: 低分阈值（低于此分数未完成得0分）
]]
function ScoringSystem.new(config)
    local self = setmetatable({}, ScoringSystem)

    self.config = config or {}

    self.K_base = self.config.K_base or 32
    self.S_max = self.config.S_max or 3000
    self.initial_score = self.config.initial_score or 1000
    self.min_score = self.config.min_score or 0
    self.low_score_threshold = self.config.low_score_threshold or 1000

    return self
end

--[[
    计算预期胜率（标准ELO公式）
    @param score_a: number 玩家A的分数
    @param score_b: number 玩家B的分数
    @return number 玩家A的预期胜率（0-1）
    
    公式：E = 1 / (1 + 10^((Rb - Ra) / 400))
    - 当A分数高于B时，预期胜率大于0.5
    - 分数差400分，预期胜率约为0.91
]]
function ScoringSystem:calculateExpectedScore(score_a, score_b)
    return 1 / (1 + 10 ^ ((score_b - score_a) / 400))
end

--[[
    计算动态K值
    @param score: number 当前玩家分数
    @return number 动态K值（整数）
    
    作用：分数越高，K值越小，加分越少，扣分越多
    - 分数为0时，K = K_base
    - 分数达到S_max时，K = K_base * 0.5
]]
function ScoringSystem:calculateDynamicK(score)
    local normalized = math.max(0, math.min(score / self.S_max, 1))
    return math.floor(self.K_base * (1 - normalized * 0.5))
end

--[[
    普通匹配计分（炉石模式）
    @param playerScores: table 玩家当前分数 { [seat] = score }
    @param rankings: table 排名列表 { { seat, rank, usedTime, eliminated } }
    @return table 计分结果 { [seat] = { oldScore, newScore, delta, rank, reason } }
    
    计分规则：
    1. 完成游戏的玩家根据ELO系统计算分数变化
    2. 未完成的玩家：
       - 分数 < low_score_threshold：+0分（保护低分玩家）
       - 分数 >= low_score_threshold：扣分
    3. 排名越高，实际得分越高；分数越高，加分越少
]]
function ScoringSystem:calculateMatchScore(playerScores, rankings)
    local results = {}
    local finishedPlayers = {}

    -- 筛选出已完成的玩家
    for _, r in ipairs(rankings) do
        if r.rank > 0 then
            table.insert(finishedPlayers, r)
        end
    end

    -- 按排名排序
    table.sort(finishedPlayers, function(a, b)
        return a.rank < b.rank
    end)

    -- 玩家数不足2人时不计算分数变化
    if #finishedPlayers < 2 then
        for _, r in ipairs(rankings) do
            local score = playerScores[r.seat] or self.initial_score
            results[r.seat] = {
                oldScore = math.floor(score),
                newScore = math.floor(score),
                delta = 0,
                reason = "not_enough_players"
            }
        end
        return results
    end

    -- 计算所有完成玩家的平均分
    local totalScore = 0
    for _, r in ipairs(finishedPlayers) do
        local score = playerScores[r.seat] or self.initial_score
        totalScore = totalScore + score
    end
    local avgScore = totalScore / #finishedPlayers

    -- 遍历每个玩家计算分数
    for _, r in ipairs(rankings) do
        local seat = r.seat
        local oldScore = playerScores[seat] or self.initial_score
        local k = self:calculateDynamicK(oldScore)

        -- 未完成的玩家：扣分最多
        if r.rank == 0 then
            -- 直接扣K值（最多扣分）
            local delta = -math.floor(k)
            local newScore = math.floor(math.max(self.min_score, oldScore + delta))
            results[seat] = {
                oldScore = math.floor(oldScore),
                newScore = newScore,
                delta = delta,
                reason = "unfinished"
            }
        else
            -- 已完成的玩家：基于平均分计算ELO分数变化
            local totalPlayers = #finishedPlayers

            -- 计算相对于平均分的预期胜率
            local expected = self:calculateExpectedScore(oldScore, avgScore)

            -- 计算实际得分：排名越高越接近1
            -- 第1名 actual=1，最后一名 actual接近0
            local rank = r.rank
            local actual = 1 - (rank - 1) / math.max(1, totalPlayers - 1)

            -- 根据实际与预期的差异计算分数变化
            -- actual > expected：加分（表现超预期）
            -- actual < expected：扣分（表现低于预期）
            local delta = 0
            if actual > expected then
                delta = math.floor(k * (actual - expected) * 2)
            else
                delta = -math.floor(k * (expected - actual) * 2)
            end

            local newScore = math.floor(math.max(self.min_score, oldScore + delta))
            results[seat] = {
                oldScore = math.floor(oldScore),
                newScore = newScore,
                delta = delta,
                rank = rank,
                expected = expected,
                actual = actual,
                reason = "finished"
            }
        end
    end

    return results
end

--[[
    私人房计分
    @param playerCnt: number 游戏人数
    @param rankings: table 排名列表 { { seat, rank, usedTime, eliminated } }
    @return table 计分结果 { [seat] = { rank, score, reason } }
    
    计分规则：
    - 第1名：playerCnt 分
    - 第2名：playerCnt - 1 分
    - 第3名：playerCnt - 2 分
    - ...
    - 未完成：0分
]]
function ScoringSystem:calculatePrivateScore(playerCnt, rankings)
    local results = {}

    for _, r in ipairs(rankings) do
        local seat = r.seat
        local score = 0

        -- 已完成的玩家按排名得分
        if r.rank > 0 then
            score = playerCnt - r.rank + 1
            if score < 0 then
                score = 0
            end
        else
            -- 未完成得0分
            score = 0
        end

        results[seat] = {
            rank = r.rank,
            score = score,
            reason = r.rank > 0 and "finished" or "unfinished"
        }
    end

    return results
end

return ScoringSystem
