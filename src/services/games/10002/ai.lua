--[[
    ai.lua
    连连看游戏AI模块 - 机器人逻辑
    职责：管理机器人的游戏行为（自动消除方块）
    通过 roomHandlerAi 与 Room 通信
    
    AI逻辑：
    1. 每 AI_TICK_INTERVAL 秒执行一次判断
    2. 有 AI_ACTION_PROBABILITY 概率执行消除
    3. 从可消除方块对中随机选择一对进行消除
]]

local log = require "log"
local config = require "games.10002.configLogic"

local aiHandler = {}
local aiLogic = {}
local XY = {}  -- 消息处理函数表

-- AI数据存储 { [seat] = { stepid, lastActionTime, mapData, ... } }
aiLogic.data = {}

-- Room -> AI 的通信接口
aiLogic.roomHandlerAi = nil

-- 加载游戏配置
local gameConfig = require "games.10002.config"

-- AI配置（从config读取，可调整）
aiLogic.config = {
    TICK_INTERVAL = gameConfig.AI and gameConfig.AI.TICK_INTERVAL or 5,           -- 执行间隔（秒）
    ACTION_PROBABILITY = gameConfig.AI and gameConfig.AI.ACTION_PROBABILITY or 70, -- 行动概率（百分比）
}

--[[
    ==================== AI核心逻辑 ====================
]]

--[[
    设置AI配置
    @param cfg: table { tickInterval, actionProbability }
]]
function aiHandler.setConfig(cfg)
    if cfg then
        aiLogic.config.TICK_INTERVAL = cfg.tickInterval or aiLogic.config.TICK_INTERVAL
        aiLogic.config.ACTION_PROBABILITY = cfg.actionProbability or aiLogic.config.ACTION_PROBABILITY
    end
    log.info("[AI] 配置更新: 间隔=%d秒, 概率=%d%%", 
        aiLogic.config.TICK_INTERVAL, aiLogic.config.ACTION_PROBABILITY)
end

--[[
    获取AI配置
    @return table 当前配置
]]
function aiHandler.getConfig()
    return aiLogic.config
end

--[[
    AI执行消除操作
    @param seat: number 机器人座位号
]]
function aiLogic.doEliminate(seat)
    log.info("[AI] 座位%d尝试消除", seat)
    
    local data = aiLogic.data[seat]
    if not data then
        log.warn("[AI] 座位%d数据不存在", seat)
        return
    end
    
    -- 检查当前阶段是否为 PLAYING
    if data.stepid ~= config.GAME_STEP.PLAYING then
        log.debug("[AI] 座位%d当前不在PLAYING阶段，跳过", seat)
        return
    end
    
    -- 检查概率
    local rand = math.random(1, 100)
    if rand > aiLogic.config.ACTION_PROBABILITY then
        log.debug("[AI] 座位%d本次不执行消除 (随机数:%d > 概率:%d)", 
            seat, rand, aiLogic.config.ACTION_PROBABILITY)
        return
    end
    
    -- 获取可消除的方块对（从logicHandler获取）
    local validPairs = aiLogic.roomHandlerAi.getValidPairs(seat)
    if not validPairs or #validPairs == 0 then
        log.debug("[AI] 座位%d没有可消除的方块对", seat)
        return
    end
    
    -- 随机选择一对进行消除
    local pairIndex = math.random(1, #validPairs)
    local pair = validPairs[pairIndex]
    
    log.info("[AI] 座位%d执行消除: (%d,%d) -> (%d,%d)", 
        seat, pair[1].row, pair[1].col, pair[2].row, pair[2].col)
    
    -- 构建消除请求参数（注意：转换为客户端坐标0-based）
    local args = {
        row1 = pair[1].row - 1,
        col1 = pair[1].col - 1,
        row2 = pair[2].row - 1,
        col2 = pair[2].col - 1,
    }
    
    -- 调用logicHandler的clickTiles接口
    aiLogic.roomHandlerAi.onAiMsg(seat, "clickTiles", args)
    
    -- 更新最后行动时间
    data.lastActionTime = os.time()
end

--[[
    开始新的游戏阶段
    @param seat: number 座位号
    @param stepid: number 阶段ID
]]
function aiLogic.startStep(seat, stepid)
    aiLogic.data[seat] = aiLogic.data[seat] or {}
    aiLogic.data[seat].stepid = stepid
    aiLogic.data[seat].stepBeginTime = os.time()
    
    log.info("[AI] 座位%d进入阶段%d", seat, stepid)
    
    -- 如果是PLAYING阶段，初始化最后行动时间
    if stepid == config.GAME_STEP.PLAYING then
        aiLogic.data[seat].lastActionTime = os.time()
    end
end

--[[
    更新AI状态（定时调用）
]]
function aiLogic.update()
    local now = os.time()
    
    for seat, data in pairs(aiLogic.data) do
        -- 只在PLAYING阶段执行AI逻辑
        if data.stepid == config.GAME_STEP.PLAYING then
            local timeSinceLastAction = now - (data.lastActionTime or 0)
            
            -- 检查是否达到该AI独立的执行间隔
            local interval = data.tickInterval or aiLogic.config.TICK_INTERVAL
            if timeSinceLastAction >= interval then
                aiLogic.doEliminate(seat)
            end
        end
    end
end

--[[
    清理指定座位的AI数据
    @param seat: number 座位号
]]
function aiLogic.clearSeat(seat)
    if aiLogic.data[seat] then
        aiLogic.data[seat] = nil
        log.info("[AI] 清理座位%d数据", seat)
    end
end

--[[
    清理所有AI数据
]]
function aiLogic.clearAll()
    aiLogic.data = {}
    log.info("[AI] 清理所有数据")
end

--[[
    ==================== 消息处理 ====================
]]

--[[
    收到阶段变更消息
    @param seat: number 座位号
    @param data: table { step }
]]
function XY.stepId(seat, data)
    aiLogic.startStep(seat, data.step)
end

--[[
    收到游戏开始消息
    @param seat: number 座位号
    @param data: table 游戏开始数据
]]
function XY.gameStart(seat, data)
    aiLogic.data[seat] = aiLogic.data[seat] or {}
    aiLogic.data[seat].roundNum = data.roundNum
    log.info("[AI] 座位%d游戏开始，局数:%d", seat, data.roundNum)
end

--[[
    收到地图数据消息
    @param seat: number 座位号
    @param data: table { mapData, totalBlocks }
]]
function XY.mapData(seat, data)
    aiLogic.data[seat] = aiLogic.data[seat] or {}
    -- 可以在这里解析和存储地图数据，如果需要AI做更复杂的决策
    log.debug("[AI] 座位%d收到地图数据", seat)
end

--[[
    收到消除成功消息
    @param seat: number 座位号
    @param data: table 消除结果
]]
function XY.tilesRemoved(seat, data)
    if data.code == 1 then
        log.debug("[AI] 座位%d消除成功，剩余方块:%d", data.seat, data.remaining)
    end
end

--[[
    收到游戏结束消息
    @param seat: number 座位号
    @param data: table 游戏结束数据
]]
function XY.gameEnd(seat, data)
    aiLogic.clearSeat(seat)
    log.info("[AI] 座位%d游戏结束", seat)
end

--[[
    收到玩家完成消息
    @param seat: number 座位号
    @param data: table { seat, usedTime, rank }
]]
function XY.playerFinished(seat, data)
    if seat == data.seat then
        log.info("[AI] 座位%d已完成游戏，用时:%d秒，排名:%d", 
            seat, data.usedTime, data.rank)
    end
end

--[[
    ==================== 对外接口 ====================
]]

--[[
    AI收到消息（由roomHandlerAi调用）
    @param seat: number 座位号
    @param name: string 消息名
    @param data: table 消息数据
]]
function aiHandler.onMsg(seat, name, data)
    if XY[name] then
        XY[name](seat, data)
    else
        log.debug("[AI] 未处理的消息: %s", name)
    end
end

--[[
    初始化AI模块（由Room调用）
    @param roomHandlerAi: table Room提供的回调接口
    @param robotCnt: number 机器人数量
]]
function aiHandler.init(roomHandlerAi, robotCnt)
    aiLogic.roomHandlerAi = roomHandlerAi
    aiLogic.clearAll()
    log.info("[AI] 初始化完成，机器人数量:%d", robotCnt or 0)
end

--[[
    更新AI（由Room定时调用）
]]
function aiHandler.update()
    aiLogic.update()
end

--[[
    添加机器人（当机器人加入房间时调用）
    @param seat: number 座位号
]]
function aiHandler.addRobot(seat)
    -- 随机生成执行间隔 3-6 秒
    local tickInterval = math.random(3, 6)
    aiLogic.data[seat] = {
        stepid = config.GAME_STEP.NONE,
        lastActionTime = 0,
        tickInterval = tickInterval,  -- 每个AI独立的执行间隔
    }
    log.info("[AI] 添加机器人座位%d，执行间隔:%d秒", seat, tickInterval)
end

--[[
    移除机器人（当机器人离开房间时调用）
    @param seat: number 座位号
]]
function aiHandler.removeRobot(seat)
    aiLogic.clearSeat(seat)
end

return aiHandler
