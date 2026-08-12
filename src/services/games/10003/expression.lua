--[[
    expression.lua
    算24点(10003)表达式校验模块
    功能：
    1. 分词与语法解析（支持 + - * / 括号、一元负号、多位数）
    2. 分数精确四则运算（避免浮点误差，如 8/(3-8/3)=24 用浮点会算错）
    3. 校验表达式结果是否等于目标值(24)
    4. 校验表达式中使用的数字集合与发牌数字完全一致（每个数字恰好用一次）
    本模块不依赖skynet/log，可独立单元测试。
]]

local expression = {}

-- 分数统一用 {n=分子, d=分母} 表示，始终约分且分母为正

-- 最大公约数
local function gcd(a, b)
    a = math.abs(a)
    b = math.abs(b)
    while b ~= 0 do
        a, b = b, a % b
    end
    return a
end

-- 构造分数（约分），分母为0返回nil
function expression.fraction(n, d)
    if d == 0 then
        return nil
    end
    if d < 0 then
        n, d = -n, -d
    end
    local g = gcd(n, d)
    return { n = n / g, d = d / g }
end

-- 分数加减乘除，除数为0返回nil
function expression.add(a, b)
    return expression.fraction(a.n * b.d + b.n * a.d, a.d * b.d)
end

function expression.sub(a, b)
    return expression.fraction(a.n * b.d - b.n * a.d, a.d * b.d)
end

function expression.mul(a, b)
    return expression.fraction(a.n * b.n, a.d * b.d)
end

function expression.div(a, b)
    if b.n == 0 then
        return nil
    end
    return expression.fraction(a.n * b.d, a.d * b.n)
end

-- 比较两个分数是否相等
function expression.equal(a, b)
    return a.n == b.n and a.d == b.d
end

-- 是否等于整数
function expression.isInteger(a)
    return a.d == 1
end

--[[
    分词器
    @param str string 表达式字符串
    @return table|nil token列表, string|nil 错误信息
    token: {type="num", value=数字} | {type="op", value="+|-|*|/"} | {type="lparen"|"rparen"}
]]
local function tokenize(str)
    local tokens = {}
    local i = 1
    local len = #str
    while i <= len do
        local c = str:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c:match("%d") then
            local start = i
            while i <= len and str:sub(i, i):match("%d") do
                i = i + 1
            end
            local num = tonumber(str:sub(start, i - 1))
            if not num then
                return nil, "数字解析失败"
            end
            table.insert(tokens, { type = "num", value = num })
        elseif c == "+" or c == "-" or c == "*" or c == "/" then
            table.insert(tokens, { type = "op", value = c })
            i = i + 1
        elseif c == "(" then
            table.insert(tokens, { type = "lparen" })
            i = i + 1
        elseif c == ")" then
            table.insert(tokens, { type = "rparen" })
            i = i + 1
        else
            return nil, "包含非法字符: " .. c
        end
    end
    return tokens
end

-- 递归下降解析器
local Parser = {}
Parser.__index = Parser

local function newParser(tokens)
    return setmetatable({ tokens = tokens, pos = 1 }, Parser)
end

function Parser:peek()
    return self.tokens[self.pos]
end

function Parser:next()
    local t = self.tokens[self.pos]
    self.pos = self.pos + 1
    return t
end

-- expr := term (('+'|'-') term)*
function Parser:parseExpr()
    local left = self:parseTerm()
    if not left then
        return nil
    end
    while true do
        local t = self:peek()
        if not t or t.type ~= "op" or (t.value ~= "+" and t.value ~= "-") then
            return left
        end
        self:next()
        local right = self:parseTerm()
        if not right then
            return nil
        end
        if t.value == "+" then
            left = expression.add(left, right)
        else
            left = expression.sub(left, right)
        end
        if not left then
            return nil
        end
    end
end

-- term := factor (('*'|'/') factor)*
function Parser:parseTerm()
    local left = self:parseFactor()
    if not left then
        return nil
    end
    while true do
        local t = self:peek()
        if not t or t.type ~= "op" or (t.value ~= "*" and t.value ~= "/") then
            return left
        end
        self:next()
        local right = self:parseFactor()
        if not right then
            return nil
        end
        if t.value == "*" then
            left = expression.mul(left, right)
        else
            left = expression.div(left, right)
        end
        if not left then
            return nil
        end
    end
end

-- factor := ('+'|'-') factor | number | '(' expr ')'
function Parser:parseFactor()
    local t = self:peek()
    if not t then
        return nil
    end
    if t.type == "op" and (t.value == "+" or t.value == "-") then
        self:next()
        local v = self:parseFactor()
        if not v then
            return nil
        end
        if t.value == "-" then
            return expression.fraction(-v.n, v.d)
        end
        return v
    elseif t.type == "num" then
        self:next()
        return expression.fraction(t.value, 1)
    elseif t.type == "lparen" then
        self:next()
        local v = self:parseExpr()
        if not v then
            return nil
        end
        local r = self:next()
        if not r or r.type ~= "rparen" then
            return nil
        end
        return v
    end
    return nil
end

--[[
    解析并求值表达式
    @param str string 表达式字符串
    @return fraction|nil 成功返回分数（{n=分子, d=分母}）
    @return string|nil 失败返回错误信息
]]
function expression.evaluate(str)
    if not str or str == "" then
        return nil, "表达式为空"
    end
    local tokens, err = tokenize(str)
    if not tokens then
        return nil, err
    end
    local parser = newParser(tokens)
    local value = parser:parseExpr()
    if not value then
        return nil, "表达式语法错误"
    end
    -- 必须消费完所有token（防 "1+2)" 这类尾部多余字符）
    if parser:peek() then
        return nil, "表达式语法错误"
    end
    return value
end

--[[
    校验玩家提交的算式
    @param exprStr string 玩家提交的算式
    @param numbers table 本局发牌数字 {n1,n2,n3,n4}（无序）
    @return boolean 是否通过
    @return string 失败原因（成功时为nil）
    @return fraction 结果分数（成功时返回）
]]
function expression.validate(exprStr, numbers)
    if not exprStr or exprStr == "" then
        return false, "表达式为空"
    end
    -- 长度保护，防超大输入（正常算式远小于此长度）
    if #exprStr > 200 then
        return false, "表达式过长"
    end

    local value, err = expression.evaluate(exprStr)
    if not value then
        return false, err
    end

    -- 检查结果是否等于24
    if not (value.n == 24 and value.d == 1) then
        return false, "结果不等于24"
    end

    -- 检查使用的数字与发牌数字集合一致（每个数字恰好用一次，不允许其他数字）
    local tokens, tokErr = tokenize(exprStr)
    if not tokens then
        return false, tokErr
    end
    local usedCount = {}
    local expectedCount = {}
    for _, n in ipairs(numbers) do
        expectedCount[n] = (expectedCount[n] or 0) + 1
    end
    for _, t in ipairs(tokens) do
        if t.type == "num" then
            local n = t.value
            if not expectedCount[n] then
                return false, "使用了未发牌的数字: " .. n
            end
            usedCount[n] = (usedCount[n] or 0) + 1
            if usedCount[n] > expectedCount[n] then
                return false, "数字 " .. n .. " 使用次数超过发牌次数"
            end
        end
    end
    for n, cnt in pairs(expectedCount) do
        if (usedCount[n] or 0) ~= cnt then
            return false, "数字 " .. n .. " 未全部使用"
        end
    end

    return true, nil, value
end

return expression
