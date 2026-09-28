--[[
    questionSource.lua
    算24点(10003)出题唯一入口：出题策略 + 获取题目（策略、取数、校验、回退全部收敛在本文件）
    职责分层：
      1. 策略层：决定"走题库还是本地随机"与题库难度（plan/roll/normalizePrivateDifficulty/racePlan）
      2. 取题层：getQuestion（普通局单题）/ getRaceQuestionSet（竞速批量），必返回可用题
      3. 校验层：validateBankResp/validateNumbers，统一题库响应与数字字段校验
      4. 难度权重：题库难度 1-5 权重随机（原 difficulty.lua 并入）
    规则来源（产品设定）：
      匹配房：10% 走题库，题库难度按权重 30/30/20/15/5
      私人房按难度等级（客户端上抛 key = difficulty）：
        0 随机：50% 本地随机 / 50% 题库，题库难度 1-5 均匀随机
        1 简单：纯本地随机，不走题库
        2 中等：走题库，难度 1-3 均匀随机
        3 困难：走题库，难度 3-5 均匀随机
      竞速：racePlan(difficulty)，当前所有难度统一最简本地随机（config.RACE.DIFFICULTY 预留）
    依赖注入：题库跨服务调用经 ctx.callBank 传入（room 组装闭包），日志走 log 模块（离线单测可桩）；
    本模块不直接依赖 skynet，可用 Lua 解释器离线单测。回退保证：未命中概率、题库异常、返回/字段非法一律回退
    solver.deal（保证有解），取题接口永远返回可用题目。
]]

local log = require "log"
local solver = require "games.10003.solver"
local configLogic = require "games.10003.configLogic"
local gameConfig = require "games.10003.config"

local source = {}

-- ==================== 难度权重（原 difficulty.lua 并入） ====================

-- 题库难度权重表（改这里即可调整题库难度分布）：难度1 30%、2 30%、3 20%、4 15%、5 5%
source.DIFFICULTY_WEIGHTS = {
    { id = 1, weight = 30 },
    { id = 2, weight = 30 },
    { id = 3, weight = 20 },
    { id = 4, weight = 15 },
    { id = 5, weight = 5 },
}

-- 权重总和
function source.totalWeight()
    local total = 0
    for _, item in ipairs(source.DIFFICULTY_WEIGHTS) do
        total = total + item.weight
    end
    return total
end

--[[
    按权重随机一个题库难度id（原 difficulty.roll）
    @param randomFn function|nil 随机源，入参为权重总和，返回 [1, total] 的整数；默认用 math.random
    @return number 难度id
]]
function source.rollDifficulty(randomFn)
    local total = source.totalWeight()
    local value
    if randomFn then
        value = randomFn(total)
    else
        value = math.random(1, total)
    end

    local acc = 0
    for _, item in ipairs(source.DIFFICULTY_WEIGHTS) do
        acc = acc + item.weight
        if value <= acc then
            return item.id
        end
    end
    return source.DIFFICULTY_WEIGHTS[#source.DIFFICULTY_WEIGHTS].id
end

-- ==================== 策略层 ====================

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
    规整私人房难度：非法值一律按"随机(0)"处理
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
        return true, source.rollDifficulty()
    end
    return true, math.random(plan.min or 1, plan.max or 5)
end

--[[
    竞速玩法出题计划（预留接口）：返回该难度的出题计划
    当前：所有难度（0随机/1简单/2中等/3困难）统一返回最简本地随机计划；
    将来接入题库/难度权重时改 config.RACE.DIFFICULTY 与此处即可生效，不动调用链
    （raceLogic/roomHandler.getRaceQuestionSet 消费）。
    @param difficulty any 难度等级（非法值按随机0处理，与 normalizePrivateDifficulty 一致）
    @return table 计划 { source=来源标记, difficultyId, numberMin, numberMax }
]]
function source.racePlan(difficulty)
    local id = source.normalizePrivateDifficulty(difficulty)
    -- 每难度出题配置预留：config.RACE.DIFFICULTY[id]（暂空表，将来填 source/difficultyId/numberMin/numberMax 即生效）
    local raceConf = (type(gameConfig.RACE) == "table" and type(gameConfig.RACE.DIFFICULTY) == "table")
        and gameConfig.RACE.DIFFICULTY[id] or nil
    if type(raceConf) == "table" then
        return {
            source = raceConf.source or "local",
            difficultyId = raceConf.difficultyId,
            numberMin = raceConf.numberMin,
            numberMax = raceConf.numberMax,
        }
    end
    -- 最简本地随机计划：数字范围交由调用方（ctx.numberMin/numberMax，来自 room 的 rule）决定
    return { source = "local" }
end

-- ==================== 校验层 ====================

--[[
    校验题目数字字段：必须为 DEAL_COUNT 个整数
    @param numbers any
    @return boolean
]]
function source.validateNumbers(numbers)
    if type(numbers) ~= "table" or #numbers ~= configLogic.DEAL_COUNT then
        return false
    end
    for _, n in ipairs(numbers) do
        if type(n) ~= "number" or n % 1 ~= 0 then
            return false
        end
    end
    return true
end

--[[
    校验题库响应：code==1、data 为表、data.numbers 字段合法
    @param resp any 题库返回
    @return table|nil 合法的数字表
    @return any 题号（data.id，可能为 nil）
]]
function source.validateBankResp(resp)
    if type(resp) ~= "table" or resp.code ~= 1 or type(resp.data) ~= "table" then
        return nil
    end
    local data = resp.data
    if not source.validateNumbers(data.numbers) then
        return nil
    end
    return data.numbers, data.id
end

-- ==================== 取题层 ====================

--[[
    走题库取一道题（题库调用经 ctx.callBank 依赖注入，本模块不碰 skynet/集群）
    任何失败（未注册/抛异常/响应或字段非法）返回 nil，由调用方回退本地随机。
    @param ctx table 取题上下文
    @param difficultyId number 题库难度id
    @return table|nil 4个数字
]]
local function fetchFromBank(ctx, difficultyId)
    if type(ctx.callBank) ~= "function" then
        return nil
    end
    local opts = { excludeIds = ctx.recentIds or {} }
    local ok, resp = pcall(ctx.callBank, ctx.gameid, difficultyId, opts)
    if not ok then
        log.error("%s [Source] 题库服务调用异常(难度%s): %s", ctx.logTag or "", tostring(difficultyId), tostring(resp))
        return nil
    end
    local numbers, id = source.validateBankResp(resp)
    if not numbers then
        log.error("%s [Source] 题库返回异常或字段非法(难度%s)", ctx.logTag or "", tostring(difficultyId))
        return nil
    end
    -- 题号去重记录（同一房间短期内不重复出题）
    if type(id) == "string" and id ~= "" and type(ctx.recentIds) == "table" then
        table.insert(ctx.recentIds, id)
        local limit = ctx.recentLimit or 30
        while #ctx.recentIds > limit do
            table.remove(ctx.recentIds, 1)
        end
    end
    log.info("%s [Source] 题库取题成功 难度%s 题号%s 数字%s", ctx.logTag or "",
        tostring(difficultyId), tostring(id), table.concat(numbers, ","))
    return numbers
end

--[[
    普通局取题（唯一入口）：策略掷骰 -> 命中题库则取题，未命中/失败回退本地随机
    @param ctx table { isMatchRoom, difficulty, gameid, numberMin, numberMax, recentIds, recentLimit, callBank, logTag }
    @return table numbers 4个数字（必有）
    @return number|nil difficultyId 走题库时的难度id
    @return boolean fromBank 是否来自题库
]]
function source.getQuestion(ctx)
    ctx = ctx or {}
    local plan = source.plan(ctx.isMatchRoom, ctx.difficulty)
    local useBank, difficultyId = source.roll(plan)
    if useBank then
        local bankNumbers = fetchFromBank(ctx, difficultyId)
        if bankNumbers then
            return bankNumbers, difficultyId, true
        end
    end
    return solver.deal(ctx.numberMin, ctx.numberMax), nil, false
end

--[[
    竞速取题（唯一入口）：按 racePlan 计划生成 count 道题，任何失败回退本地随机
    @param ctx table 同 getQuestion
    @param count number 题数（白名单已由 room/raceLogic 双重规整）
    @return table questions[i] = { numbers = {n1,n2,n3,n4} }（必有 count 道）
]]
function source.getRaceQuestionSet(ctx, count)
    ctx = ctx or {}
    local plan = source.racePlan(ctx.difficulty)
    local min = ctx.numberMin
    local max = ctx.numberMax
    if type(plan) == "table" then
        min = tonumber(plan.numberMin) or min
        max = tonumber(plan.numberMax) or max
    end

    local questions = {}
    for i = 1, count do
        local numbers = nil
        -- 预留外部题源入口：plan.source ~= "local" 时走题库（当前 racePlan 恒为 local，此路预留）
        if type(plan) == "table" and plan.source ~= nil and plan.source ~= "local" then
            numbers = fetchFromBank(ctx, plan.difficultyId)
        end
        if not numbers or not source.validateNumbers(numbers) then
            -- 回退：本地随机出题（solver.deal 保证有解）
            numbers = solver.deal(min, max)
        end
        questions[i] = { numbers = numbers }
    end
    return questions
end

return source
