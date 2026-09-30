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
      竞速（好友房 playMode=1）：按题号顺序分段出题，分段表 config.RACE.DIFFICULTY：
        0 随机：前50%本地随机，后50%题库d1-d5随机
        1 简单：全部本地随机
        2 中等：前50%本地随机，后50%题库d1-d3随机
        3 困难：前20%本地随机，中间60%题库d1-d3随机，后20%题库d4-d5随机
        分段边界按累计占比四舍五入落题号；题库失败逐题回退本地随机
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
    竞速玩法出题分段计划：返回该难度的分段数组（config.RACE.DIFFICULTY[id]）
    分段校验：每段 pct>0、source∈{local,bank}、bank 段 dMin/dMax 为 1~5 整数且 dMin<=dMax、
    各段 pct 合计 100（容差0.01）；任一不满足打 error 并整场回退全本地随机（保证竞速一定能开）。
    @param difficulty any 难度等级（非法值按随机0处理，与 normalizePrivateDifficulty 一致）
    @return table segments 分段数组 { pct, source="local"/"bank", dMin, dMax }
]]
function source.racePlan(difficulty)
    local FALLBACK = { { pct = 100, source = "local" } }
    local id = source.normalizePrivateDifficulty(difficulty)
    local segments = (type(gameConfig.RACE) == "table" and type(gameConfig.RACE.DIFFICULTY) == "table")
        and gameConfig.RACE.DIFFICULTY[id] or nil
    if type(segments) ~= "table" or #segments == 0 then
        return FALLBACK
    end
    local sum = 0
    for _, seg in ipairs(segments) do
        local pct = (type(seg) == "table") and tonumber(seg.pct) or nil
        if not pct or pct <= 0 then
            log.error("[Source] 竞速分段非法(pct)，难度%s，回退全本地随机", tostring(id))
            return FALLBACK
        end
        if seg.source ~= "local" and seg.source ~= "bank" then
            log.error("[Source] 竞速分段非法(source=%s)，难度%s，回退全本地随机", tostring(seg.source), tostring(id))
            return FALLBACK
        end
        if seg.source == "bank" then
            local dMin, dMax = tonumber(seg.dMin), tonumber(seg.dMax)
            if not dMin or not dMax or dMin % 1 ~= 0 or dMax % 1 ~= 0 or dMin < 1 or dMax > 5 or dMin > dMax then
                log.error("[Source] 竞速分段非法(bank难度区间 %s~%s)，难度%s，回退全本地随机",
                    tostring(seg.dMin), tostring(seg.dMax), tostring(id))
                return FALLBACK
            end
        end
        sum = sum + pct
    end
    if math.abs(sum - 100) > 0.01 then
        log.error("[Source] 竞速分段占比合计%s(不等于100)，难度%s，回退全本地随机", tostring(sum), tostring(id))
        return FALLBACK
    end
    return segments
end

--[[
    按题号取所在分段：边界 bound_k = floor(count × 累计占比% + 0.5)（四舍五入落题号），
    第 k 段覆盖题号 bound_{k-1}+1 ~ bound_k，末段强制覆盖到 count（余数全落末段）。
    @param segments racePlan 返回的分段数组
    @param index number 题号 1..count
    @param count number 总题数
    @return table 所在分段 { pct, source, dMin, dMax }
]]
local function segmentAt(segments, index, count)
    local cum = 0
    for k, seg in ipairs(segments) do
        cum = cum + seg.pct
        local bound = (k == #segments) and count or math.floor(count * cum / 100 + 0.5)
        if index <= bound then
            return seg
        end
    end
    return segments[#segments]
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
    竞速取题（唯一入口）：按 racePlan 分段计划生成 count 道题，任何失败回退本地随机
    分段按题号顺序落段（竞速共享题序一次性生成，题号即做题顺序）：
    段 source="bank" 时在 [dMin,dMax] 均匀掷难度id走题库，题库任何失败（服务未登记/
    返回异常/字段非法）仅该题回退本地随机，不影响整场；本地随机数字范围沿用 ctx（room rule）。
    @param ctx table 同 getQuestion
    @param count number 题数（白名单已由 room/raceLogic 双重规整）
    @return table questions[i] = { numbers = {n1,n2,n3,n4} }（必有 count 道）
]]
function source.getRaceQuestionSet(ctx, count)
    ctx = ctx or {}
    local segments = source.racePlan(ctx.difficulty)
    local min = ctx.numberMin
    local max = ctx.numberMax

    local questions = {}
    for i = 1, count do
        local seg = segmentAt(segments, i, count)
        local numbers = nil
        if seg.source == "bank" then
            local difficultyId = math.random(seg.dMin, seg.dMax)
            numbers = fetchFromBank(ctx, difficultyId)
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
