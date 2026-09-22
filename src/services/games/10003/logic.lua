--[[
    logic.lua
    算24点(10003)单局游戏逻辑
    职责：管理一局游戏的生命周期（发牌、答题校验、排名、结算）
    通过 roomHandler 与 Room 通信

    游戏阶段：
    1. START (1秒): 发牌，下发4个数字（求解器保证有解）
    2. PLAYING (可配，默认60秒): 玩家提交算式。第一个答对者不再立即结束本局，
       而是把剩余时间压缩到最多10秒（参考10002），给其余玩家（含AI）最后抢答机会；
       所有人答对或倒计时归零后进入结算
    3. END (0秒): 结算排名与分数（含每位答对者的算式与用时）

    校验规则：
    1. 表达式结果必须等于24（分数精确运算，支持 8/(3-8/3) 这类分数中间结果）
    2. 表达式中4个数字必须与发牌数字完全一致（每个数字恰好用一次）

    注意：本模块只负责一局游戏，多局管理由 Room 控制
    每局开始时 Room 会重新调用 init 初始化
]]

local config = require("games.10003.configLogic")
local log = require "log"
local expression = require "games.10003.expression"
local solver = require "games.10003.solver"
local skynet = require "skynet"

local logic = {gameid = 0, roomid = 0}
local function getRoomLogTag()
    return string.format("[%d][%d]", logic.gameid, logic.roomid)
end

-- 单局状态
logic.dealNumbers = {}          -- 本局4个数字
logic.dealStartTimeMs = 0       -- 发牌时间(毫秒)，用于计算答对用时
logic.playerProgress = {}       -- 玩家进度 { [seat] = { finished, submitTime, expression, rank, usedTime } }
logic.roomHandler = nil         -- Room 提供的回调接口
logic.rule = {}                 -- 游戏规则
logic.seatMap = {}              -- 逻辑座位 -> 房间座位（由Room建立绑定后传入）
logic.binit = false             -- 是否初始化
logic.stepId = config.GAME_STEP.NONE  -- 当前阶段ID
logic.stepBeginTime = 0         -- 阶段开始时间
logic.roundNum = 0              -- 当前局数
logic.endType = config.END_TYPE.NONE  -- 本局结束类型
logic.gameStatus = config.GAME_STATUS.NONE  -- 游戏状态
logic.startTime = 0             -- 本局开始时间
logic.finishOrder = 0           -- 本局答对顺序计数器（排名依据，第一个答对者为1）

-- 逻辑座位 -> 房间座位（无映射时回退为自身，保证逻辑可独立使用）
local function toRoomSeat(seat)
    return logic.seatMap[seat] or seat
end

-- 暴露给 Room 的接口
local logicHandler = {}

--[[
    ==================== 阶段管理核心函数 ====================
]]

-- 获取当前阶段ID
function logic.getStepId()
    return logic.stepId
end

-- 获取阶段时间限制（秒）
function logic.getStepTimeLen(stepid)
    return config.STEP_TIME_LEN[stepid] or 0
end

-- 设置阶段开始时间
function logic.setStepBeginTime()
    logic.stepBeginTime = os.time()
end

--[[
    开始一个新的阶段
    @param stepid: number 阶段ID (GAME_STEP.START/PLAYING/END)
]]
function logic.startStep(stepid)
    log.info("%s [Logic] 开始阶段 %d", getRoomLogTag(), stepid)

    logic.setStepBeginTime()
    logic.stepId = stepid

    logic.roomHandler.sendToAll("stepId", {
        step = stepid,
    })

    if stepid == config.GAME_STEP.START then
        logic.startStepStart()
    elseif stepid == config.GAME_STEP.PLAYING then
        logic.startStepPlaying()
    elseif stepid == config.GAME_STEP.END then
        logic.startStepEnd()
    end
end

--[[
    停止当前阶段
    @param stepid: number 阶段ID
]]
function logic.stopStep(stepid)
    log.info("%s [Logic] 停止阶段 %d", getRoomLogTag(), stepid)

    if stepid == config.GAME_STEP.START then
        logic.stopStepStart()
    elseif stepid == config.GAME_STEP.PLAYING then
        logic.stopStepPlaying()
    elseif stepid == config.GAME_STEP.END then
        logic.stopStepEnd()
    end
end

--[[
    阶段超时处理
    @param stepid: number 阶段ID
]]
function logic.onStepTimeout(stepid)
    log.info("%s [Logic] 阶段 %d 超时", getRoomLogTag(), stepid)

    if stepid == config.GAME_STEP.START then
        logic.onStepStartTimeout()
    elseif stepid == config.GAME_STEP.PLAYING then
        logic.onStepPlayingTimeout()
    elseif stepid == config.GAME_STEP.END then
        logic.onStepEndTimeout()
    end
end

--[[
    ==================== START 阶段 ====================
]]

-- START阶段开始：发牌并广播4个数字
function logic.startStepStart()
    log.info("%s [Logic] START阶段开始", getRoomLogTag())

    logic._deal()
    logic._initPlayerProgress()
    logic.startTime = os.time()
    logic.dealStartTimeMs = math.floor(skynet.time() * 1000)

    logic.roomHandler.sendToAll("dealCards", {
        roundNum = logic.roundNum,
        numbers = logic.dealNumbers,
        timeLimit = config.STEP_TIME_LEN[config.GAME_STEP.PLAYING],
        startTime = logic.startTime,
    })
end

-- START阶段停止：进入PLAYING阶段
function logic.stopStepStart()
    log.info("%s [Logic] START阶段停止", getRoomLogTag())
    logic.startStep(config.GAME_STEP.PLAYING)
end

-- START阶段超时处理
function logic.onStepStartTimeout()
    logic.stopStep(config.GAME_STEP.START)
end

--[[
    ==================== PLAYING 阶段 ====================
]]

-- PLAYING阶段开始：下发答题倒计时
function logic.startStepPlaying()
    log.info("%s [Logic] PLAYING阶段开始，玩家可以开始答题", getRoomLogTag())

    logic.roomHandler.sendToAll("gameClock", {
        time = config.STEP_TIME_LEN[config.GAME_STEP.PLAYING],
        seat = 0,
    })
end

function logic.stopStepPlaying()
    logic.startStep(config.GAME_STEP.END)
end

-- PLAYING阶段超时处理（参考10002 onStepPlayingTimeout）：
-- 无人答对 -> 本局无胜者(TIMEOUT)；已有人答对（第一个答对者把剩余时间压缩到10秒后到点）-> 正常结算(WIN)
function logic.onStepPlayingTimeout()
    if logic._checkAllUnfinished() then
        log.info("%s [Logic] PLAYING阶段超时，无人答对，本局无胜者", getRoomLogTag())
        logic.endType = config.END_TYPE.TIMEOUT
    else
        log.info("%s [Logic] PLAYING阶段超时，已有玩家答对，正常结算", getRoomLogTag())
        logic.endType = config.END_TYPE.WIN
    end
    logic.stopStep(config.GAME_STEP.PLAYING)
end

--[[
    ==================== END 阶段 ====================
]]

function logic.startStepEnd()
    logicHandler.endGame()
end

-- END阶段停止：清理阶段状态
function logic.stopStepEnd()
    logic.stepId = config.GAME_STEP.NONE
end

-- END阶段超时处理（END阶段时间为0，不会触发）
function logic.onStepEndTimeout()
end

--[[
    ==================== 初始化 & 游戏控制 ====================
]]

--[[
    重置/初始化逻辑模块（每局开始时调用）
    @param rule: table 游戏规则 { playerCnt, maxTime, numberMin, numberMax }
    @param roomHandler: table Room 提供的回调接口
]]
function logicHandler.init(rule, roomHandler, gameid, roomid)
    logic.gameid = gameid or 0
    logic.roomid = roomid or 0
    log.info("%s [Logic] 初始化单局游戏逻辑", getRoomLogTag())

    -- 重置所有状态（关键：每局必须完全重置）
    logic.dealNumbers = {}
    logic.dealStartTimeMs = 0
    logic.playerProgress = {}
    logic.startTime = 0
    logic.gameStatus = config.GAME_STATUS.NONE
    logic.stepId = config.GAME_STEP.NONE
    logic.stepBeginTime = 0
    logic.roundNum = 0
    logic.endType = config.END_TYPE.NONE
    logic.finishOrder = 0

    logic.rule = rule or {}
    logic.seatMap = logic.rule.seatMap or {}
    logic.roomHandler = roomHandler
    logic.binit = true

    -- 默认规则
    logic.rule.playerCnt = logic.rule.playerCnt or 2
    logic.rule.maxTime = logic.rule.maxTime or 30
    logic.rule.numberMin = logic.rule.numberMin or 1
    logic.rule.numberMax = logic.rule.numberMax or 9
    logic.rule.endTime = logic.rule.endTime or 10   -- 第一个答对者触发的剩余时间封顶值(秒)

    -- 更新PLAYING阶段时间（本局答题时限）
    config.STEP_TIME_LEN[config.GAME_STEP.PLAYING] = logic.rule.maxTime

    log.info("%s [Logic] 单局初始化完成，玩家数: %d，答题时限: %d秒，数字范围: %d-%d",
        getRoomLogTag(), logic.rule.playerCnt, logic.rule.maxTime, logic.rule.numberMin, logic.rule.numberMax)
end

--[[
    发牌：先问 Room 要题库题目（是否走题库、用哪个难度由 Room 按房间类型与难度等级决定），
    取不到则保留原有本地随机生成逻辑
    说明：题库只决定题目内容，不影响“本局一定能发到牌”——未命中概率、题库异常或字段非法
    都回退到 solver.deal（保证有解）
]]
function logic._deal()
    local bankNumbers = nil

    if logic.roomHandler and logic.roomHandler.getDealNumbersFromBank then
        local ok, numbers = pcall(logic.roomHandler.getDealNumbersFromBank)
        if not ok then
            log.error("%s [Logic] 题库取题异常，回退本地随机: %s", getRoomLogTag(), tostring(numbers))
        elseif type(numbers) == "table" and #numbers == config.DEAL_COUNT then
            bankNumbers = numbers
        end
    end

    if bankNumbers then
        logic.dealNumbers = bankNumbers
        log.info("%s [Logic] 第%d局发牌(题库): %s", getRoomLogTag(), logic.roundNum, table.concat(bankNumbers, ","))
        return
    end

    logic.dealNumbers = solver.deal(logic.rule.numberMin, logic.rule.numberMax)
    log.info("%s [Logic] 第%d局发牌(本地随机): %s", getRoomLogTag(), logic.roundNum, table.concat(logic.dealNumbers, ","))
end

-- 初始化玩家进度
function logic._initPlayerProgress()
    for seat = 1, logic.rule.playerCnt do
        logic.playerProgress[seat] = {
            finished = false,   -- 是否已答对
            submitTime = 0,     -- 答对提交时间(ms)
            expression = "",    -- 答对算式
            rank = 0,           -- 排名
            usedTime = 0,       -- 用时(ms)
        }
    end
end

--[[
    统计本局答对情况（参考10002 logic._checkAllFinished）
    @return allFinished: boolean 是否所有人都已答对
            finishedPlayers: number 已答对人数
            totalPlayers: number 本局玩家总数
]]
function logic._checkAllFinished()
    local allFinished = true
    local finishedPlayers = 0
    local totalPlayers = 0

    for _, progress in pairs(logic.playerProgress) do
        totalPlayers = totalPlayers + 1
        if progress.finished then
            finishedPlayers = finishedPlayers + 1
        else
            allFinished = false
        end
    end

    return allFinished, finishedPlayers, totalPlayers
end

--[[
    检查是否所有玩家都还未答对（参考10002 logic._checkAllUnfinished）
    @return boolean 是否无人答对
]]
function logic._checkAllUnfinished()
    for _, progress in pairs(logic.playerProgress) do
        if progress.finished then
            return false
        end
    end
    return true
end

--[[
    开始一局游戏
    @param roundNum: number 当前局数（由 Room 传入）
]]
function logicHandler.startGame(roundNum)
    roundNum = roundNum or 1
    logic.roundNum = roundNum

    log.info("%s [Logic] 开始第%d局游戏", getRoomLogTag(), roundNum)

    if not logic.binit then
        log.error("%s [Logic] 游戏逻辑未初始化，请先调用 init()", getRoomLogTag())
        return false
    end

    logic.dealNumbers = {}
    logic.dealStartTimeMs = 0
    logic.playerProgress = {}
    logic.startTime = os.time()
    logic.gameStatus = config.GAME_STATUS.PLAYING
    logic.stepId = config.GAME_STEP.NONE
    logic.stepBeginTime = 0
    logic.endType = config.END_TYPE.NONE

    logic.roomHandler.sendToAll("gameStart", {
        roundNum = roundNum,
        startTime = logic.startTime,
        brelink = 0,
    })

    logic.startStep(config.GAME_STEP.START)

    log.info("%s [Logic] 第%d局游戏开始，玩家数: %d", getRoomLogTag(), roundNum, logic.rule.playerCnt)
    return true
end

--[[
    ==================== 玩家操作处理 ====================
]]

--[[
    处理玩家提交算式
    @param seat: number 玩家座位
    @param args: table { expression = 算式字符串 }
    @return table { code, msg, rank }
]]
function logicHandler.submitAnswer(seat, args)
    -- 检查当前阶段
    if logic.stepId ~= config.GAME_STEP.PLAYING then
        log.warn("%s [Logic] 座位%d提交时不在答题阶段", getRoomLogTag(), seat)
        return {code = 0, msg = "当前不在答题阶段"}
    end

    local exprStr = args and args.expression or ""
    log.info("%s [Logic] 座位%d提交算式: %s", getRoomLogTag(), seat, exprStr)

    local progress = logic.playerProgress[seat]
    if not progress then
        log.warn("%s [Logic] 座位%d不在本局游戏中", getRoomLogTag(), seat)
        return {code = 0, msg = "玩家不在本局游戏中"}
    end
    if progress.finished then
        log.warn("%s [Logic] 座位%d本局已答对，不能重复提交", getRoomLogTag(), seat)
        return {code = 0, msg = "本局已答对，不能重复提交"}
    end

    -- 校验：结果等于24且恰好使用发牌的4个数字各一次
    local ok, err = expression.validate(exprStr, logic.dealNumbers)
    if not ok then
        log.info("%s [Logic] 座位%d提交错误: %s", getRoomLogTag(), seat, err)
        -- 广播错误提交（分发给其他玩家）
        logic.roomHandler.sendToAll("answerResult", {
            seat = toRoomSeat(seat),
            expression = exprStr,
            correct = 0,
            rank = 0,
        })
        return {code = 0, msg = err or "算式错误"}
    end

    -- 答对：锁定玩家，按答对先后顺序排名（不再立即结束本局）
    local nowMs = math.floor(skynet.time() * 1000)
    progress.finished = true
    progress.submitTime = nowMs
    progress.expression = exprStr
    logic.finishOrder = logic.finishOrder + 1
    progress.rank = logic.finishOrder
    progress.usedTime = math.max(0, nowMs - logic.dealStartTimeMs)

    logic.endType = config.END_TYPE.WIN

    log.info("%s [Logic] 座位%d答对，答案[%s]，用时%dms，排名%d",
        getRoomLogTag(), seat, exprStr, progress.usedTime, progress.rank)

    -- 广播正确提交（携带算式与排名，供客户端即时展示）
    logic.roomHandler.sendToAll("answerResult", {
        seat = toRoomSeat(seat),
        expression = exprStr,
        correct = 1,
        rank = progress.rank,
    })

    logic.roomHandler.onPlayerFinish(seat, progress.usedTime, progress.rank)

    -- 参考10002 logic._onPlayerFinish：第一个答对者触发"剩余时间封顶"。
    -- 若本阶段剩余时间超过 endCountdown(默认10秒)，则把剩余时间压缩为 endCountdown 秒，
    -- 让其余玩家（含AI）还有最后抢答机会；剩余时间不足10秒则保持不变。
    -- 与10002做法一致：直接改写 config.STEP_TIME_LEN[PLAYING]，update() 依此判定超时。
    if progress.rank == 1 then
        local endCountdown = logic.rule.endTime or 10
        local elapsed = os.time() - logic.stepBeginTime
        local remaining = config.STEP_TIME_LEN[config.GAME_STEP.PLAYING] - elapsed

        if remaining > endCountdown then
            config.STEP_TIME_LEN[config.GAME_STEP.PLAYING] = elapsed + endCountdown
            logic.roomHandler.sendToAll("gameClock", {
                time = endCountdown,
                seat = 0,
            })
            log.info("%s [Logic] 第一个玩家答对，剩余时间压缩为%d秒", getRoomLogTag(), endCountdown)
        else
            log.info("%s [Logic] 第一个玩家答对，剩余时间%d秒不超过%d秒，不压缩", getRoomLogTag(), remaining, endCountdown)
        end
    end

    -- 若所有人都已答对，本局立即结束；否则继续等待其余玩家答题（由倒计时归零或全员答对结束）
    local allFinished, finishedPlayers, totalPlayers = logic._checkAllFinished()
    if allFinished and totalPlayers > 0 then
        log.info("%s [Logic] 全部玩家已答对(%d/%d)，本局结束", getRoomLogTag(), finishedPlayers, totalPlayers)
        logic.stopStep(config.GAME_STEP.PLAYING)
    end

    return {code = 1, msg = "回答正确", rank = progress.rank}
end

--[[
    ==================== 游戏结束 ====================
]]

-- 结束本局游戏：组装排名、计分、广播
function logicHandler.endGame()
    if logic.gameStatus == config.GAME_STATUS.END then
        log.warn("%s [Logic] 本局已结束，跳过", getRoomLogTag())
        return
    end

    log.info("%s [Logic] 本局游戏结束，类型: %d", getRoomLogTag(), logic.endType)

    logic.gameStatus = config.GAME_STATUS.END
    local endTime = os.time()

    -- 组装本局排名：答对者rank>0（携带算式与用时，用于结算下发），未答对者rank=0
    -- 协议 gameEnd.rankings(RankingInfo) 已含 expression/usedTime/rank 字段，无需新增协议
    local rankings = {}
    for seat, progress in pairs(logic.playerProgress) do
        if progress.finished then
            table.insert(rankings, {
                seat = toRoomSeat(seat),
                expression = progress.expression,
                usedTime = progress.usedTime,
                rank = progress.rank,
            })
        else
            table.insert(rankings, {
                seat = toRoomSeat(seat),
                expression = "",
                usedTime = -1,
                rank = 0,
            })
        end
    end

    -- 稳定排序：答对者按排名升序在前，未答对者(rank=0)在后，同档按座位升序，保证结算列表顺序确定
    table.sort(rankings, function(a, b)
        if a.rank ~= b.rank then
            if a.rank == 0 then return false end
            if b.rank == 0 then return true end
            return a.rank < b.rank
        end
        return a.seat < b.seat
    end)

    -- 调用room计分接口获取分数
    local scores = logic.roomHandler.gameResult(logic.endType, rankings)

    -- 发送gameEnd协议（包含分数）
    logic.roomHandler.sendToAll("gameEnd", {
        roundNum = logic.roundNum,
        endTime = endTime,
        endType = logic.endType,
        rankings = rankings,
        scores = scores,
    })

    logic.roomHandler.onGameEnd(logic.endType, rankings)

    logic.stopStep(config.GAME_STEP.END)
end

--[[
    ==================== 重连 ====================
]]

-- 玩家重连：补发本局状态
function logicHandler.relink(seat)
    log.info("%s [Logic] 座位%d重连", getRoomLogTag(), seat)

    local progress = logic.playerProgress[seat]
    if not progress then
        log.warn("%s [Logic] 座位%d数据不存在，无法重连", getRoomLogTag(), seat)
        return
    end

    -- 补发基本状态
    logic.roomHandler.sendToSeat(seat, "gameRelink", {
        startTime = logic.startTime,
    })
    logic.roomHandler.sendToSeat(seat, "stepId", {
        step = logic.stepId,
    })
    logic.roomHandler.sendToSeat(seat, "gameStart", {
        roundNum = logic.roundNum,
        startTime = logic.startTime,
        brelink = 1,
    })

    -- 补发本局数字
    logic.roomHandler.sendToSeat(seat, "dealCards", {
        roundNum = logic.roundNum,
        numbers = logic.dealNumbers,
        timeLimit = config.STEP_TIME_LEN[config.GAME_STEP.PLAYING],
        startTime = logic.startTime,
    })

    -- 补发已发生的答对提交
    for targetSeat, p in pairs(logic.playerProgress) do
        if p.finished then
            logic.roomHandler.sendToSeat(seat, "answerResult", {
                seat = toRoomSeat(targetSeat),
                expression = p.expression,
                correct = 1,
                rank = p.rank,
            })
        end
    end

    -- PLAYING阶段补发剩余时间
    if logic.stepId == config.GAME_STEP.PLAYING then
        local elapsed = os.time() - logic.stepBeginTime
        local totalTime = config.STEP_TIME_LEN[config.GAME_STEP.PLAYING]
        local remainingTime = totalTime - elapsed
        if remainingTime > 0 then
            logic.roomHandler.sendToSeat(seat, "gameClock", {
                time = remainingTime,
                seat = 0,
            })
        end
    end
end

--[[
    ==================== 定时更新 ====================
]]

-- 定时更新（每帧调用，检查阶段超时）
function logicHandler.update()
    if not logic.binit then
        return
    end

    local stepid = logic.getStepId()
    if stepid == config.GAME_STEP.NONE or stepid == config.GAME_STEP.END then
        return
    end

    local currentTime = os.time()
    local timeLen = currentTime - logic.stepBeginTime

    if timeLen >= logic.getStepTimeLen(stepid) then
        logic.onStepTimeout(stepid)
    end
end

--[[
    ==================== 查询接口 ====================
]]

-- 获取本局4个数字（供AI使用）
function logicHandler.getDealNumbers()
    return logic.dealNumbers
end

-- 获取本局游戏状态
function logicHandler.getGameStatus()
    return {
        status = logic.gameStatus,
        startTime = logic.startTime,
        stepId = logic.stepId,
        playerProgress = logic.playerProgress,
    }
end

-- 获取本局排名信息（供 Room 统计多局战绩）
function logicHandler.getRankings()
    local rankings = {}
    for seat, progress in pairs(logic.playerProgress) do
        table.insert(rankings, {
            seat = seat,
            finished = progress.finished,
            usedTime = progress.usedTime or -1,
            rank = progress.rank,
        })
    end
    return rankings
end

return logicHandler
