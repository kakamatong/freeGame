--[[
    difficulty.lua
    算24点(10003)题目难度分布
    职责：按产品设定的权重随机难度id，供 Room 向题库服务取题时使用。
    权重：难度1 30%、难度2 30%、难度3 20%、难度4 15%、难度5 5%
    说明：本模块不依赖 skynet，可用 Lua 解释器离线单测（支持注入随机源）。
]]

local difficulty = {}

-- 难度权重表（改这里即可调整出题难度分布）
difficulty.WEIGHTS = {
    { id = 1, weight = 30 },
    { id = 2, weight = 30 },
    { id = 3, weight = 20 },
    { id = 4, weight = 15 },
    { id = 5, weight = 5 },
}

--[[
    权重总和
    @return number 总和
]]
function difficulty.totalWeight()
    local total = 0
    for _, item in ipairs(difficulty.WEIGHTS) do
        total = total + item.weight
    end
    return total
end

--[[
    按权重随机一个难度id
    @param randomFn function|nil 随机源，入参为权重总和，返回 [1, total] 的整数；默认用 math.random
    @return number 难度id
]]
function difficulty.roll(randomFn)
    local total = difficulty.totalWeight()
    local value
    if randomFn then
        value = randomFn(total)
    else
        value = math.random(1, total)
    end

    local acc = 0
    for _, item in ipairs(difficulty.WEIGHTS) do
        acc = acc + item.weight
        if value <= acc then
            return item.id
        end
    end
    return difficulty.WEIGHTS[#difficulty.WEIGHTS].id
end

return difficulty
