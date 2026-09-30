--[[
    raceLogic.lua
    算24点(10003)好友房「竞速玩法」单场逻辑（privateRule.playMode=1 时启用）
    与 logic.lua（单局状态机）平行：仅竞速模式走本模块，logic.lua 保持零改动（普通模式零回归风险）。

    玩法（2026-09-28 产品拍板）：
    1. 全员同一题序：开局一次生成 N 道题（shared），所有人题目一模一样、顺序相同
    2. 答错只重试不推进：错误只回 submitAnswer response，不广播、不推进题号（防共享题序泄题）
    3. 纯速度不限单题时限；整场保护时限 config.RACE.MAX_DURATION（默认1800秒，可配），
       到点强制 raceFinish(endType=2) 按当前进度排名
    4. 谁先答完全部 N 题 -> 竞速立即结束 -> raceFinish -> totalResult 大结算 -> roomEnd（一房一竞速）
    5. 排名：完成者按完成时间升序（先答完全部者 rank=1）；
       未完成者按 finishedCount 降序 -> lastAnswerTimeMs 升序 -> seat 升序
    6. 计分复用 scoring.calculatePrivateScore（playerCnt-rank+1），由 room.gameResult 执行

    协议（proto/game10003/s2c.sproto）：
    - raceQuestion 37：只单发本人当前题（questionIndex/totalQuestions/numbers/startTime/timeLimit）
    - raceProgress 38：每次推进广播全量进度快照（<=6人，天然重同步），重连补同一份
    - raceFinish 39：广播竞速结束（endType/winnerSeat/questionCount/rankings）

    时钟口径：毫秒用 skynet.time()*1000（与 logic.dealStartTimeMs 同口径）；
    lastAnswerTimeMs 语义 = 达成当前 finishedCount 的时刻（最近一次答对时刻，未答对为开赛时刻），
    用于同进度玩家比"谁更早做到"。
]]

local config = require("games.10003.config")
local configLogic = require("games.10003.configLogic")
local log = require "log"
local expression = require "games.10003.expression"
local solver = require "games.10003.solver"
local skynet = require "skynet"

-- 竞速状态
local RACE_STATUS = {
    NONE = 0,    -- 未开始
    PLAYING = 1, -- 进行中
    ENDED = 2,   -- 已结束
}

-- 竞速结束类型（对应 raceFinish.endType）
local RACE_END_TYPE = {
    NONE = 0,
    FINISH = 1,  -- 有人完赛
    TIMEOUT = 2, -- 整场保护时限到
}

local race = { gameid = 0, roomid = 0 }

local function getRoomLogTag()
    return string.format("[%d][%d]", race.gameid, race.roomid)
end

-- 当前毫秒时间（与 logic.dealStartTimeMs 同口径）
local function nowMs()
    return math.floor(skynet.time() * 1000)
end

-- 逻辑座位 -> 房间座位（无映射时回退为自身，保证逻辑可独立使用/离线测试）
local function toRoomSeat(seat)
    return race.seatMap[seat] or seat
end

-- ==================== 竞速状态 ====================
race.status = RACE_STATUS.NONE
race.totalQuestions = 0 -- 总题数 N
race.questions = {}     -- 共享题序 questions[i] = { numbers = {n1,n2,n3,n4} }
race.players = {}       -- players[logicSeat] = 玩家进度
race.startTimeMs = 0    -- 开赛毫秒时间
race.startWallTime = 0  -- 开赛秒级时间（下发协议用）
race.roundNum = 0       -- 局数（竞速一局，恒为1，兼容 gameStart 字段）
race.endType = RACE_END_TYPE.NONE
race.winnerSeat = 0     -- 完赛者逻辑座位（超时结束为0）
race.finishData = nil   -- 终态快照（重连终态恢复用）
race.roomHandler = nil
race.rule = {}
race.seatMap = {}
race.binit = false

-- 暴露给 Room 的接口
local raceHandler = {}

--[[    ==================== 纯函数（可离线断言） ==================== ]]

--[[
    玩法模式白名单规整（纯函数）
    @param value any 客户端上抛的 privateRule.playMode
    @return number config.PLAY_MODE.RACE(1) 或 config.PLAY_MODE.NORMAL(0)，非法值回退普通
]]
function raceHandler.normalizePlayMode(value)
    local n = tonumber(value)
    if n == config.PLAY_MODE.RACE then
        return config.PLAY_MODE.RACE
    end
    return config.PLAY_MODE.NORMAL
end

--[[
    竞速题数白名单规整（纯函数）：白名单 config.RACE.QUESTION_COUNTS 之外一律回退默认
    @param value any 客户端上抛的 privateRule.raceQuestionCount
    @return number 白名单内题数或 config.RACE.DEFAULT_QUESTION_COUNT
]]
function raceHandler.normalizeQuestionCount(value)
    local n = tonumber(value)
    if not n then
        return config.RACE.DEFAULT_QUESTION_COUNT
    end
    for _, allowed in ipairs(config.RACE.QUESTION_COUNTS) do
        if n == allowed then
            return n
        end
    end
    return config.RACE.DEFAULT_QUESTION_COUNT
end

--[[
    竞速排名（纯函数，可离线断言）
    规则：完成者按完成时间升序在前（先答完全部者 rank=1）；
          未完成者按 finishedCount 降序 -> lastAnswerTimeMs 升序 -> seat 升序
    @param players table 玩家进度 { [seat] = { finished, finishedCount, finishTimeMs, lastAnswerTimeMs } }
    @param startTimeMs number 开赛毫秒时间
    @return table 排名数组 { { seat, finished, finishedCount, usedTimeMs, rank } ... }（seat 为传入的座位）
]]
function raceHandler.rankPlayers(players, startTimeMs)
    local list = {}
    for seat, p in pairs(players) do
        local endMs = (p.finished and p.finishTimeMs) or p.lastAnswerTimeMs or startTimeMs
        table.insert(list, {
            seat = seat,
            finished = p.finished and true or false,
            finishedCount = p.finishedCount or 0,
            usedTimeMs = math.max(0, (endMs or startTimeMs) - startTimeMs),
            finishTimeMs = p.finishTimeMs or 0,
            lastAnswerTimeMs = p.lastAnswerTimeMs or startTimeMs,
        })
    end
    table.sort(list, function(a, b)
        -- 完成者整体在前
        if a.finished ~= b.finished then
            return a.finished
        end
        if a.finished then
            -- 完成者按完成时间升序（先答完者靠前）
            if a.finishTimeMs ~= b.finishTimeMs then
                return a.finishTimeMs < b.finishTimeMs
            end
        else
            -- 未完成者：finishedCount 降序 -> lastAnswerTimeMs 升序 -> seat 升序
            if a.finishedCount ~= b.finishedCount then
                return a.finishedCount > b.finishedCount
            end
            if a.lastAnswerTimeMs ~= b.lastAnswerTimeMs then
                return a.lastAnswerTimeMs < b.lastAnswerTimeMs
            end
        end
        return a.seat < b.seat
    end)
    for i, item in ipairs(list) do
        item.rank = i
    end
    return list
end

--[[    ==================== 内部工具 ==================== ]]

-- 组装进度快照（raceProgress 全量下发；每次推进与重连都用这一份）
function race._buildProgressSnapshot()
    local players = {}
    for seat = 1, race.rule.playerCnt do
        local p = race.players[seat]
        if p then
            local endMs = (p.finished and p.finishTimeMs) or p.lastAnswerTimeMs
            table.insert(players, {
                seat = toRoomSeat(seat),
                questionIndex = math.min(p.questionIndex, race.totalQuestions),
                finishedCount = p.finishedCount,
                usedTimeMs = math.max(0, endMs - race.startTimeMs),
                status = p.finished and 1 or 0,
            })
        end
    end
    return players
end

-- 组装某玩家当前题下发内容（raceQuestion）
function race._questionMsg(seat)
    local p = race.players[seat]
    local idx = math.min(p.questionIndex, race.totalQuestions)
    local q = race.questions[idx]
    return {
        questionIndex = idx,
        totalQuestions = race.totalQuestions,
        numbers = q and q.numbers or {},
        startTime = race.startWallTime,
        timeLimit = config.RACE.QUESTION_TIME, -- 0=不限时（单题时限预留）
    }
end

--[[
    生成共享题序：优先走 Room 取题预留接口 roomHandler.getRaceQuestionSet，
    任何失败（接口不存在/pcall 捕获异常/返回结构非法/字段非法）回退本地随机
    count × solver.deal(numberMin, numberMax)，保证竞速一定能开。
    @return table questions[i] = { numbers = {n1,n2,n3,n4} }
]]
function race._buildQuestions()
    local count = race.totalQuestions
    local min = race.rule.numberMin or config.NUMBER_RANGE.MIN
    local max = race.rule.numberMax or config.NUMBER_RANGE.MAX
    local questions = {}

    if race.roomHandler and race.roomHandler.getRaceQuestionSet then
        local ok, set = pcall(race.roomHandler.getRaceQuestionSet, count, race.rule.difficulty)
        if ok and type(set) == "table" and #set == count then
            local valid = true
            for i = 1, count do
                local q = set[i]
                local numbers = (type(q) == "table") and q.numbers or nil
                if type(numbers) ~= "table" or #numbers ~= configLogic.DEAL_COUNT then
                    valid = false
                    break
                end
                for _, n in ipairs(numbers) do
                    if type(n) ~= "number" or n % 1 ~= 0 then
                        valid = false
                        break
                    end
                end
                if not valid then
                    break
                end
            end
            if valid then
                for i = 1, count do
                    questions[i] = { numbers = set[i].numbers }
                end
                log.info("%s [Race] 共享题序生成成功(取题接口) %d 题", getRoomLogTag(), count)
                return questions
            end
        end
        log.error("%s [Race] getRaceQuestionSet 异常或字段非法，回退本地随机: %s",
            getRoomLogTag(), tostring(set))
    end

    -- 回退：count × solver.deal（本地随机出题，保证有解）
    for i = 1, count do
        questions[i] = { numbers = solver.deal(min, max) }
    end
    log.info("%s [Race] 共享题序生成成功(本地随机) %d 题", getRoomLogTag(), count)
    return questions
end

--[[    ==================== 竞速结束 ==================== ]]

--[[
    竞速结束（内部）：计算排名 -> 计分复用 -> 广播 raceFinish -> 通知 Room 走 roomEnd
    （roomEnd 内部下发 totalResult 大结算，不走 HALFTIME/再来一局）
    @param endType number RACE_END_TYPE.FINISH(1) 或 RACE_END_TYPE.TIMEOUT(2)
    @param winnerSeat number|nil 完赛者逻辑座位（超时结束传 nil）
]]
function race._finishRace(endType, winnerSeat)
    if race.status == RACE_STATUS.ENDED then
        return
    end
    race.status = RACE_STATUS.ENDED
    race.endType = endType
    race.winnerSeat = winnerSeat or 0

    -- 排名（纯函数），再把座位换成房间座位下发
    local ranked = raceHandler.rankPlayers(race.players, race.startTimeMs)
    local rankings = {}
    for _, item in ipairs(ranked) do
        table.insert(rankings, {
            seat = toRoomSeat(item.seat),
            finishedCount = item.finishedCount,
            usedTimeMs = item.usedTimeMs,
            rank = item.rank,
        })
    end

    race.finishData = {
        endType = endType,
        winnerSeat = toRoomSeat(race.winnerSeat),
        questionCount = race.totalQuestions,
        rankings = rankings,
    }

    log.info("%s [Race] 竞速结束 endType=%d winnerSeat=%d", getRoomLogTag(), endType, race.finishData.winnerSeat)

    -- 计分复用 scoring.calculatePrivateScore(playerCnt-rank+1)，由 room.gameResult 执行
    if race.roomHandler and race.roomHandler.gameResult then
        race.roomHandler.gameResult(endType, rankings)
    end

    -- 广播竞速结束（客户端据此跳过小结算、直接进大结算）
    race.roomHandler.sendToAll("raceFinish", race.finishData)

    -- 通知 Room：竞速一房一场，直接 roomEnd（内部下发 totalResult + roomEnd）
    if race.roomHandler and race.roomHandler.onRaceEnd then
        race.roomHandler.onRaceEnd(endType, rankings)
    end
end

--[[    ==================== 初始化 & 开局 ==================== ]]

--[[
    重置/初始化竞速逻辑（每场开始时调用，与 logicHandler.init 同签名）
    @param rule table { playerCnt, numberMin, numberMax, seatMap, totalQuestions, maxDuration, difficulty }
    @param roomHandler table Room 提供的回调接口
]]
function raceHandler.init(rule, roomHandler, gameid, roomid)
    race.gameid = gameid or 0
    race.roomid = roomid or 0
    log.info("%s [Race] 初始化竞速逻辑", getRoomLogTag())

    race.status = RACE_STATUS.NONE
    race.totalQuestions = 0
    race.questions = {}
    race.players = {}
    race.startTimeMs = 0
    race.startWallTime = 0
    race.roundNum = 0
    race.endType = RACE_END_TYPE.NONE
    race.winnerSeat = 0
    race.finishData = nil

    race.rule = rule or {}
    race.seatMap = race.rule.seatMap or {}
    race.roomHandler = roomHandler
    race.binit = true

    -- 默认规则（与 logic.lua 同风格兜底）
    race.rule.playerCnt = race.rule.playerCnt or 2
    race.rule.numberMin = race.rule.numberMin or config.NUMBER_RANGE.MIN
    race.rule.numberMax = race.rule.numberMax or config.NUMBER_RANGE.MAX
    race.rule.maxDuration = race.rule.maxDuration or config.RACE.MAX_DURATION
    -- 题数白名单二次规整（room.init 已规整过，这里防绕过入口直接塞非法值）
    race.totalQuestions = raceHandler.normalizeQuestionCount(race.rule.totalQuestions)

    log.info("%s [Race] 竞速初始化完成，玩家数: %d，题数: %d，保护时限: %d 秒",
        getRoomLogTag(), race.rule.playerCnt, race.totalQuestions, race.rule.maxDuration)
end

--[[
    开始竞速（与 logicHandler.startGame 同签名）：
    生成共享题序 -> 初始化玩家进度 -> 下发 gameStart/stepId(PLAYING) -> 各自第 1 题 -> 广播进度
    @param roundNum number 局数（竞速一局，兼容字段）
]]
function raceHandler.startGame(roundNum)
    roundNum = roundNum or 1
    race.roundNum = roundNum

    if not race.binit then
        log.error("%s [Race] 竞速逻辑未初始化，请先调用 init()", getRoomLogTag())
        return false
    end

    race.status = RACE_STATUS.PLAYING
    race.startWallTime = os.time()
    race.startTimeMs = nowMs()
    race.endType = RACE_END_TYPE.NONE

    -- 开局一次生成共享题序（全员同一题序、顺序相同）
    race.questions = race._buildQuestions()

    -- 玩家进度（逻辑座位 1..playerCnt）
    race.players = {}
    for seat = 1, race.rule.playerCnt do
        race.players[seat] = {
            questionIndex = 1,                   -- 当前题号（1开始）
            finishedCount = 0,                   -- 已答对题数
            lastAnswerTimeMs = race.startTimeMs, -- 达成当前进度的时刻（同进度排名 tiebreak）
            wrongCount = 0,                      -- 答错次数（不推进、仅统计）
            finished = false,
            finishTimeMs = 0,
        }
    end

    -- gameStart（brelink=0）+ stepId：竞速对外恒发 PLAYING 供客户端门控
    race.roomHandler.sendToAll("gameStart", {
        roundNum = roundNum,
        startTime = race.startWallTime,
        brelink = 0,
    })
    race.roomHandler.sendToAll("stepId", {
        step = configLogic.GAME_STEP.PLAYING,
    })

    -- 只单发本人当前题（第 1 题）+ 广播全量进度快照
    for seat = 1, race.rule.playerCnt do
        race.roomHandler.sendToSeat(seat, "raceQuestion", race._questionMsg(seat))
    end
    race.roomHandler.sendToAll("raceProgress", {
        players = race._buildProgressSnapshot(),
    })

    log.info("%s [Race] 竞速开始，第%d场，玩家数: %d", getRoomLogTag(), roundNum, race.rule.playerCnt)
    return true
end

--[[    ==================== 提交流程 ==================== ]]

--[[
    处理玩家提交算式（与 logicHandler.submitAnswer 同签名，c2s submitAnswer 复用不动）
    流程：阶段/完赛校验 -> expression.validate（逐字复用）-> 答对推进 / 答错只回 response
    @param seat number 逻辑座位
    @param args table { expression = 算式字符串 }
    @return table { code, msg, rank }
]]
function raceHandler.submitAnswer(seat, args)
    -- 1. 阶段校验：竞速已结束一律拒收
    if race.status ~= RACE_STATUS.PLAYING then
        log.warn("%s [Race] 座位%d提交时竞速已结束", getRoomLogTag(), seat)
        return { code = 0, msg = "竞速已结束", rank = 0 }
    end

    local player = race.players[seat]
    if not player then
        log.warn("%s [Race] 座位%d不在本场竞速中", getRoomLogTag(), seat)
        return { code = 0, msg = "玩家不在本局游戏中", rank = 0 }
    end

    -- 2. 已完赛者拒收
    if player.finished then
        log.warn("%s [Race] 座位%d已完赛，不能重复提交", getRoomLogTag(), seat)
        return { code = 0, msg = "已完赛，不能重复提交", rank = 0 }
    end

    local exprStr = args and args.expression or ""
    local q = race.questions[math.min(player.questionIndex, race.totalQuestions)]
    log.info("%s [Race] 座位%d提交第%d题算式: %s", getRoomLogTag(), seat, player.questionIndex, exprStr)

    -- 3. 校验：结果等于24且恰好使用本题4个数字各一次（expression.validate 逐字不动复用）
    local ok, err = expression.validate(exprStr, q and q.numbers or {})
    if not ok then
        -- 答错只重试不推进：只回 response，不广播、不推进题号
        player.wrongCount = player.wrongCount + 1
        log.info("%s [Race] 座位%d答错(第%d题): %s", getRoomLogTag(), seat, player.questionIndex, tostring(err))
        return { code = 0, msg = err or "算式错误", rank = 0 }
    end

    -- 4. 答对：推进题号、记时间
    local t = nowMs()
    player.finishedCount = player.finishedCount + 1
    player.questionIndex = player.questionIndex + 1
    player.lastAnswerTimeMs = t

    if player.questionIndex > race.totalQuestions then
        -- 第 N 题答对：立即完赛 -> 竞速立即结束
        player.finished = true
        player.finishTimeMs = t
        log.info("%s [Race] 座位%d答完全部 %d 题，用时 %dms，竞速立即结束",
            getRoomLogTag(), seat, race.totalQuestions, t - race.startTimeMs)
        race._finishRace(RACE_END_TYPE.FINISH, seat)
        return { code = 1, msg = "回答正确", rank = 0 }
    end

    -- 未到最后一题：只单发本人下一题 + 广播全量进度快照
    race.roomHandler.sendToSeat(seat, "raceQuestion", race._questionMsg(seat))
    race.roomHandler.sendToAll("raceProgress", {
        players = race._buildProgressSnapshot(),
    })

    return { code = 1, msg = "回答正确", rank = 0 }
end

--[[    ==================== 重连 ==================== ]]

--[[
    玩家重连补发（与 logicHandler.relink 同签名）：
    - 竞速进行中：gameRelink + stepId(PLAYING) + gameStart(brelink=1) + raceQuestion(当前题) + raceProgress(全量快照)
    - 竞速已结束：只回终态（stepId(END) + raceFinish 快照），不再发题
    @param seat number 逻辑座位
]]
function raceHandler.relink(seat)
    log.info("%s [Race] 座位%d重连，竞速状态=%d", getRoomLogTag(), seat, race.status)

    local player = race.players[seat]
    if not player then
        log.warn("%s [Race] 座位%d数据不存在，无法重连", getRoomLogTag(), seat)
        return
    end

    race.roomHandler.sendToSeat(seat, "gameRelink", {
        startTime = race.startWallTime,
    })

    -- 已结束：只恢复终态，不再发题
    if race.status ~= RACE_STATUS.PLAYING then
        race.roomHandler.sendToSeat(seat, "stepId", {
            step = configLogic.GAME_STEP.END,
        })
        if race.finishData then
            race.roomHandler.sendToSeat(seat, "raceFinish", race.finishData)
        end
        log.info("%s [Race] 座位%d重连：竞速已结束，只回终态", getRoomLogTag(), seat)
        return
    end

    -- 进行中：按阶段恢复题目与进度
    race.roomHandler.sendToSeat(seat, "stepId", {
        step = configLogic.GAME_STEP.PLAYING,
    })
    race.roomHandler.sendToSeat(seat, "gameStart", {
        roundNum = race.roundNum,
        startTime = race.startWallTime,
        brelink = 1,
    })
    -- 只补本人当前题 + 全量进度快照
    race.roomHandler.sendToSeat(seat, "raceQuestion", race._questionMsg(seat))
    race.roomHandler.sendToSeat(seat, "raceProgress", {
        players = race._buildProgressSnapshot(),
    })
end

--[[    ==================== 定时更新 ==================== ]]

--[[
    定时更新（Room 定时器每秒调用）：整场保护时限检查。
    纯速度玩法不限单题时限；超过 config.RACE.MAX_DURATION（默认600秒）强制按当前进度结算。
]]
function raceHandler.update()
    if not race.binit or race.status ~= RACE_STATUS.PLAYING then
        return
    end
    local maxMs = (race.rule.maxDuration or config.RACE.MAX_DURATION) * 1000
    if nowMs() - race.startTimeMs >= maxMs then
        log.info("%s [Race] 整场保护时限 %d 秒到，强制结算", getRoomLogTag(), race.rule.maxDuration)
        race._finishRace(RACE_END_TYPE.TIMEOUT, nil)
    end
end

--[[    ==================== 查询接口 ==================== ]]

-- 获取本场共享题序（供 Room/调试查询）
function raceHandler.getQuestions()
    return race.questions
end

-- 获取本场玩家进度（与 logicHandler.getGameStatus 同风格）
function raceHandler.getGameStatus()
    return {
        status = race.status,
        startTime = race.startWallTime,
        totalQuestions = race.totalQuestions,
        players = race.players,
    }
end

-- 获取本场排名（与 logicHandler.getRankings 同风格，供 Room 统计）
function raceHandler.getRankings()
    return raceHandler.rankPlayers(race.players, race.startTimeMs)
end

-- 兼容 roomHandlerAi.getDealNumbers：竞速模式无机器人，返回空表
function raceHandler.getDealNumbers()
    return {}
end

return raceHandler
