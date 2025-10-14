local RatingSystem = {}
RatingSystem.__index = RatingSystem

function RatingSystem.new(config)
    config = config or {}
    local self = setmetatable({}, RatingSystem)
    
    -- 系统参数
    self.K_base = config.K_base or 32          -- 基础调整系数
    self.S_max = config.S_max or 3000          -- 参考高分阈值
    self.initial_score = config.initial_score or 1000  -- 初始分数
    self.min_score = config.min_score or 0     -- 最低分数
    
    -- 可选：是否启用零和模式（总分守恒）
    self.zero_sum_mode = config.zero_sum_mode or false
    
    return self
end

-- 计算预期胜率
function RatingSystem:calculate_expected_score(score_a, score_b)
    return 1 / (1 + 10 ^ ((score_b - score_a) / 400))
end

-- 计算动态K值
function RatingSystem:calculate_dynamic_k(score, is_winner)
    local normalized_score = math.max(0, math.min(score / self.S_max, 1))
    
    if is_winner then
        -- 赢了：分数越高，加分越少
        return self.K_base * (1 - normalized_score)
    else
        -- 输了：分数越高，扣分越多；分数越低，扣分越少
        return self.K_base * (0.2 + 0.8 * normalized_score)
    end
end

-- 处理单场对战结果
function RatingSystem:process_match(score_a, score_b, a_wins)
    -- 计算预期胜率
    local expected_a = self:calculate_expected_score(score_a, score_b)
    local expected_b = 1 - expected_a
    
    -- 计算分数变动
    local delta_a, delta_b
    
    if a_wins then
        -- A 获胜
        delta_a = self:calculate_dynamic_k(score_a, true) * (1 - expected_a)
        delta_b = -self:calculate_dynamic_k(score_b, false) * expected_b
    else
        -- B 获胜
        delta_a = -self:calculate_dynamic_k(score_a, false) * expected_a
        delta_b = self:calculate_dynamic_k(score_b, true) * (1 - expected_b)
    end

    delta_a = math.floor(delta_a)
    delta_b = math.floor(delta_b)
    
    -- 零和模式调整：确保总分不变
    if self.zero_sum_mode then
        local total_change = delta_a + delta_b
        if total_change ~= 0 then
            local adjustment = total_change / 2
            delta_a = delta_a - adjustment
            delta_b = delta_b - adjustment
        end
    end
    
    -- 计算新分数（应用保底）
    local new_score_a = math.max(self.min_score, score_a + delta_a)
    local new_score_b = math.max(self.min_score, score_b + delta_b)
    
    -- 返回结果
    return {
        new_score_a = new_score_a,
        new_score_b = new_score_b,
        delta_a = new_score_a - score_a,
        delta_b = new_score_b - score_b,
        expected_a = expected_a,
        expected_b = expected_b
    }
end

-- 批量处理对战记录（用于测试）
function RatingSystem:process_matches(matches)
    local results = {}
    
    for i, match in ipairs(matches) do
        local result = self:process_match(match.score_a, match.score_b, match.a_wins)
        table.insert(results, result)
    end
    
    return results
end

-- 打印对战结果（调试用）
function RatingSystem:print_match_result(score_a, score_b, a_wins, result)
    local winner = a_wins and "A" or "B"
    print(string.format("对战结果: 玩家%s胜利", winner))
    print(string.format("玩家A: %d -> %d (%.1f) [预期胜率: %.1f%%]", 
        score_a, result.new_score_a, result.delta_a, result.expected_a * 100))
    print(string.format("玩家B: %d -> %d (%.1f) [预期胜率: %.1f%%]", 
        score_b, result.new_score_b, result.delta_b, result.expected_b * 100))
    print(string.format("等级: A=%s, B=%s", 
        self:get_rank_title(result.new_score_a), 
        self:get_rank_title(result.new_score_b)))
    print("---")
end

return RatingSystem