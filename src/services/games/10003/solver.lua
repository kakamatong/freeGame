--[[
    solver.lua
    算24点(10003)求解器
    功能：
    1. 给定4个数字，枚举所有组合方式（+ - * / 分数运算），求值为目标值(24)的算式
    2. 算式按“最小括号”规则拼字符串：仅保留运算优先级/结合性所必需的括号
       （如 (2*2)*(5+1) 输出 2*2*(5+1)，8/(3-8/3) 保留括号）
    3. 发牌时保证有解（deal接口）
    4. 供AI求解答案使用
    本模块仅依赖 expression.lua，可独立单元测试。
]]

local expression = require "games.10003.expression"

local solver = {}

-- 目标值
solver.TARGET = 24

-- 运算符优先级：+ - 为 1，* / 为 2；叶子数字为 3（高于任何运算符，永不需括号）
local OP_PREC = { ["+"] = 1, ["-"] = 1, ["*"] = 2, ["/"] = 2 }
local NUM_PREC = 3

-- 数字节点：{ value=分数, expr=字符串, prec=算式顶层优先级 }
local function makeNode(value, expr, prec)
    return { value = value, expr = expr, prec = prec }
end

--[[
    按最小括号规则拼接 a op b 的算式（不改变数值语义）：
    - 左子式：仅当优先级低于父运算时加括号（左结合，同级不加）
    - 右子式：优先级低于父运算，或与父运算同级且父运算为 - / 时加括号（右结合性）
    @return string 算式字符串
    @return number 该算式的顶层优先级
]]
local function exprOf(a, op, b)
    local prec = OP_PREC[op]
    local left = a.expr
    if a.prec < prec then
        left = "(" .. left .. ")"
    end
    local right = b.expr
    if b.prec < prec or (b.prec == prec and (op == "-" or op == "/")) then
        right = "(" .. right .. ")"
    end
    return left .. op .. right, prec
end

-- 对两个节点做一次指定运算（含方向），返回新节点；运算非法（除数为0）返回nil
local function combineTwo(a, op, b)
    local value
    if op == "+" then
        value = expression.add(a.value, b.value)
    elseif op == "-" then
        value = expression.sub(a.value, b.value)
    elseif op == "*" then
        value = expression.mul(a.value, b.value)
    else
        value = expression.div(a.value, b.value)
    end
    if not value then
        return nil
    end
    local expr, prec = exprOf(a, op, b)
    return makeNode(value, expr, prec)
end

-- 对两个节点做所有运算（加减乘除，减法除法各两个方向），返回新节点列表
local function combine(a, b)
    local results = {}
    local function push(node)
        if node then
            table.insert(results, node)
        end
    end
    push(combineTwo(a, "+", b))
    push(combineTwo(a, "-", b))
    push(combineTwo(b, "-", a))
    push(combineTwo(a, "*", b))
    if b.value.n ~= 0 then
        push(combineTwo(a, "/", b))
    end
    if a.value.n ~= 0 then
        push(combineTwo(b, "/", a))
    end
    return results
end

-- 递归求解：任取两个数做运算合并，直到剩一个数且值等于目标值
local function solve(nodes)
    local cnt = #nodes
    if cnt == 1 then
        if nodes[1].value.n == solver.TARGET and nodes[1].value.d == 1 then
            return nodes[1].expr
        end
        return nil
    end
    for i = 1, cnt - 1 do
        for j = i + 1, cnt do
            local rest = {}
            for k = 1, cnt do
                if k ~= i and k ~= j then
                    table.insert(rest, nodes[k])
                end
            end
            for _, newNode in ipairs(combine(nodes[i], nodes[j])) do
                local tmp = { newNode }
                for _, node in ipairs(rest) do
                    table.insert(tmp, node)
                end
                local expr = solve(tmp)
                if expr then
                    return expr
                end
            end
        end
    end
    return nil
end

--[[
    求解4个数字，返回第一个可行算式
    @param numbers table 4个数字
    @return string|nil 可行算式，无解返回nil
]]
function solver.solve(numbers)
    if not numbers or #numbers ~= 4 then
        return nil
    end
    local nodes = {}
    for _, n in ipairs(numbers) do
        table.insert(nodes, makeNode(expression.fraction(n, 1), tostring(n), NUM_PREC))
    end
    return solve(nodes)
end

--[[
    判断4个数字是否有解
    @param numbers table 4个数字
    @return boolean
]]
function solver.solvable(numbers)
    return solver.solve(numbers) ~= nil
end

-- 预置可解组合（兜底使用，全部为经典24点有解组合）
local PRESET_SOLVABLE = {
    { 3, 3, 8, 8 },  -- 8/(3-8/3)
    { 1, 5, 5, 5 },  -- 5*(5-1/5)
    { 3, 3, 7, 7 },  -- 7*(3+3/7)
    { 4, 4, 7, 7 },  -- 7*(4-4/7)
    { 1, 3, 4, 6 },  -- 6/(1-3/4)
    { 1, 4, 5, 6 },  -- 6/(5/4-1)
    { 1, 2, 7, 7 },  -- (7*7-1)/2
    { 2, 2, 6, 8 },  -- (8*2)+6+2
    { 2, 3, 5, 7 },  -- 7*(5-2)+3
    { 4, 6, 6, 9 },  -- (9-4)*6-6
}

--[[
    生成一组有解的4个数字（用于发牌）
    先随机生成并用求解器校验，无解重试；随机多次失败后从预置组合取并打乱
    @param min number 最小数字（含）
    @param max number 最大数字（含）
    @return table 4个数字（保证有解）
]]
function solver.deal(min, max)
    min = min or 1
    max = max or 9
    -- 随机生成并校验有解，最多尝试100次
    for _ = 1, 100 do
        local numbers = {
            math.random(min, max),
            math.random(min, max),
            math.random(min, max),
            math.random(min, max),
        }
        if solver.solvable(numbers) then
            return numbers
        end
    end
    -- 兜底：预置可解组合中随机选一个并打乱顺序
    local preset = PRESET_SOLVABLE[math.random(1, #PRESET_SOLVABLE)]
    local numbers = {}
    for _, n in ipairs(preset) do
        table.insert(numbers, n)
    end
    for i = #numbers, 2, -1 do
        local j = math.random(1, i)
        numbers[i], numbers[j] = numbers[j], numbers[i]
    end
    return numbers
end

return solver
