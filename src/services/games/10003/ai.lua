--[[
    ai.lua
    算24点(10003)AI模块 - 机器人逻辑
    职责：管理机器人的答题行为（按秒判定概率，命中即答题推送）
    通过 roomHandlerAi 与 Room 通信

    AI逻辑：
    1. 收到PLAYING阶段消息后，前 ACT_START_DELAY 秒(默认10秒)不答题，给真人先手空间
    2. 之后每 ROLL_INTERVAL 秒(默认1秒)掷一次 ACTION_PROBABILITY(默认5%) 的概率
    3. 命中即用solver求解本局4个数字，有解立刻答题推送；本局无解则停止判定
    4. 每次判定前检查阶段，避免第一人答对结束后机器人仍提交
]]

local skynet = require "skynet"
local log = require "log"
local config = require "games.10003.config"
local configLogic = require "games.10003.configLogic"
local solver = require "games.10003.solver"

local aiHandler = {}
local aiLogic = {gameid = 0, roomid = 0}
local function getRoomLogTag()
    return string.format("[%d][%d]", aiLogic.gameid, aiLogic.roomid)
end
local XY = {}  -- 消息处理函数表

-- AI数据 { [seat] = { stepid, attempted, ... } }
aiLogic.data = {}

-- Room -> AI 的通信接口
aiLogic.roomHandlerAi = nil

-- AI配置（从config读取，可调整）
aiLogic.config = {
    ACTION_PROBABILITY = config.AI and config.AI.ACTION_PROBABILITY or 5,  -- 每次判定的答题概率（百分比）
    ROLL_INTERVAL = config.AI and config.AI.ROLL_INTERVAL or 1,  -- 判定间隔（秒）：起解后每秒判定一次
    ACT_START_DELAY = config.AI and config.AI.ACT_START_DELAY or 10,  -- 起解前静默时长（秒）：前10秒不答题
}

--[[
    ==================== AI核心逻辑 ====================
]]

-- 处理答题：前 ACT_START_DELAY 秒不答题，之后每 ROLL_INTERVAL 秒掷一次概率，命中即答题推送
function aiLogic.dealPlay(seat)
    local data = aiLogic.data[seat]
    if not data then
        log.warn("%s [AI] 座位%d数据不存在", getRoomLogTag(), seat)
        return
    end
    if data.attempted then
        return
    end
    data.attempted = true  -- 每局只尝试一次（一次fork内按秒判定）

    local actDelay = aiLogic.config.ACT_START_DELAY or 0
    local rollInterval = aiLogic.config.ROLL_INTERVAL or 1
    local probability = aiLogic.config.ACTION_PROBABILITY or 5

    skynet.fork(function()
        -- 前 actDelay 秒不答题（给真人先手空间）
        if actDelay > 0 then
            skynet.sleep(actDelay * 100)
        end

        local rollNum = 0
        while true do
            -- 每次判定前检查阶段（对局可能已被真人答对/超时结束）
            local curData = aiLogic.data[seat]
            if not (curData and curData.stepid == configLogic.GAME_STEP.PLAYING) then
                log.info("%s [AI] 座位%d已离开PLAYING，停止判定(共判定%d次)", getRoomLogTag(), seat, rollNum)
                return
            end

            -- 每 ROLL_INTERVAL 秒掷一次概率，命中即答题推送
            rollNum = rollNum + 1
            local rand = math.random(1, 100)
            if rand <= probability then
                local numbers = aiLogic.roomHandlerAi.getDealNumbers()
                if not numbers or #numbers ~= 4 then
                    log.warn("%s [AI] 座位%d获取本局数字失败", getRoomLogTag(), seat)
                    return
                end

                local solution = solver.solve(numbers)
                if not solution then
                    log.warn("%s [AI] 座位%d本局无解，停止判定", getRoomLogTag(), seat)
                    return
                end

                log.info("%s [AI] 座位%d第%d次判定命中(随机数:%d <= 概率:%d)，答题推送: %s",
                    getRoomLogTag(), seat, rollNum, rand, probability, solution)
                aiLogic.roomHandlerAi.onAiMsg(seat, "submitAnswer", {expression = solution})
                return
            end

            log.debug("%s [AI] 座位%d第%d次判定未命中(随机数:%d > 概率:%d)", getRoomLogTag(), seat, rollNum, rand, probability)
            skynet.sleep(rollInterval * 100)
        end
    end)
end

-- 清理指定座位的AI数据
function aiLogic.clearSeat(seat)
    if aiLogic.data[seat] then
        aiLogic.data[seat] = nil
        log.info("%s [AI] 清理座位%d数据", getRoomLogTag(), seat)
    end
end

-- 清理所有AI数据
function aiLogic.clearAll()
    aiLogic.data = {}
end

--[[
    ==================== 消息处理 ====================
]]

-- 收到阶段变更消息
function XY.stepId(seat, data)
    aiLogic.data[seat] = aiLogic.data[seat] or {}
    aiLogic.data[seat].stepid = data.step

    -- PLAYING阶段：开始解题
    if data.step == configLogic.GAME_STEP.PLAYING then
        aiLogic.dealPlay(seat)
    end
end

-- 收到游戏开始消息
function XY.gameStart(seat, data)
    aiLogic.data[seat] = aiLogic.data[seat] or {}
    aiLogic.data[seat].roundNum = data.roundNum
    log.info("%s [AI] 座位%d游戏开始，局数:%d", getRoomLogTag(), seat, data.roundNum)
end

-- 收到游戏结束消息
function XY.gameEnd(seat, data)
    aiLogic.clearSeat(seat)
    log.info("%s [AI] 座位%d游戏结束", getRoomLogTag(), seat)
end

--[[
    ==================== 对外接口 ====================
]]

-- AI收到消息（由roomHandlerAi调用）
function aiHandler.onMsg(seat, name, data)
    if XY[name] then
        XY[name](seat, data)
    else
        log.debug("%s [AI] 未处理的消息: %s", getRoomLogTag(), name)
    end
end

-- 初始化AI模块（由Room调用）
function aiHandler.init(roomHandlerAi, robotCnt, gameid, roomid)
    aiLogic.gameid = gameid or 0
    aiLogic.roomid = roomid or 0
    aiLogic.roomHandlerAi = roomHandlerAi
    aiLogic.clearAll()
    log.info("%s [AI] 初始化完成，机器人数量:%d", getRoomLogTag(), robotCnt or 0)
end

-- 更新AI（由Room定时调用，本游戏AI基于fork延迟，无需每帧处理）
function aiHandler.update()
end

-- 添加机器人（当机器人加入房间时调用）
function aiHandler.addRobot(seat)
    aiLogic.data[seat] = {
        stepid = configLogic.GAME_STEP.NONE,
        attempted = false,
    }
    log.info("%s [AI] 添加机器人座位%d", getRoomLogTag(), seat)
end

-- 移除机器人（当机器人离开房间时调用）
function aiHandler.removeRobot(seat)
    aiLogic.clearSeat(seat)
end

return aiHandler
