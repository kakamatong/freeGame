--[[
    logic.lua
    连连看游戏核心逻辑模块 - 单局逻辑
    职责：管理一局游戏的生命周期（地图、消除、胜负）
    通过 roomHandler 与 Room 通信
    
    游戏阶段：
    1. START (1秒): 游戏开始，下发地图数据
    2. PLAYING (长时间): 玩家进行消除
    3. END (0秒): 游戏结束，结算
    
    注意：本模块只负责一局游戏，多局管理由 Room 控制
    每局开始时 Room 会重新调用 init 初始化
]]

local config = require("games.10002.configLogic")
local log = require "log"
local cjson = require "cjson"
local Map = require "games.10002.map"
local mapGenerator = require "games.10002.mapGenerator"

local logic = {}

-- 游戏状态（单局）
logic.playerMaps = {}           -- 玩家地图 { [seat] = Map实例 }
logic.playerProgress = {}       -- 玩家进度 { [seat] = { eliminated, startTime, finishTime, rank } }
logic.roomHandler = nil         -- Room 提供的回调接口
logic.rule = {}                 -- 游戏规则
logic.binit = false             -- 是否初始化
logic.startTime = 0             -- 游戏开始时间
logic.gameStatus = config.GAME_STATUS.NONE  -- 游戏状态

-- 游戏阶段管理（参考10001实现）
logic.stepId = config.GAME_STEP.NONE        -- 当前阶段ID
logic.stepBeginTime = 0                     -- 阶段开始时间
logic.roundNum = 0                          -- 当前局数

-- 暴露给 Room 的接口
local logicHandler = {}

--[[
    ==================== 阶段管理核心函数 ====================
]]

--[[
    获取当前阶段ID
]]
function logic.getStepId()
    return logic.stepId
end

--[[
    获取阶段时间限制（秒）
]]
function logic.getStepTimeLen(stepid)
    return config.STEP_TIME_LEN[stepid] or 0
end

--[[
    设置阶段开始时间
]]
function logic.setStepBeginTime()
    logic.stepBeginTime = os.time()
end

--[[
    开始一个新的阶段
    @param stepid: number 阶段ID (GAME_STEP.START/PLAYING/END)
]]
function logic.startStep(stepid)
    log.info("[Logic] 开始阶段 %d", stepid)
    
    logic.setStepBeginTime()
    logic.stepId = stepid
    
    -- 根据阶段调用对应的开始函数
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
    log.info("[Logic] 停止阶段 %d", stepid)
    
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
    log.info("[Logic] 阶段 %d 超时", stepid)
    
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

--[[
    START阶段开始：广播阶段ID，下发地图数据
]]
function logic.startStepStart()
    log.info("[Logic] START阶段开始")
    
    if logic.roomHandler and logic.roomHandler.sendToAll then
        logic.roomHandler.sendToAll("stepId", {
            step = config.GAME_STEP.START,
        })
    end

    logic._generatePlayerMaps()
    
    for seat, playerMap in pairs(logic.playerMaps) do
        if logic.playerProgress[seat] then
            logic.playerProgress[seat].startTime = logic.startTime
        end
    end
    
    for seat, playerMap in pairs(logic.playerMaps) do
        if logic.roomHandler and logic.roomHandler.sendToSeat then
            local totalBlocks = playerMap:getRemainingBlockCount()
            logic.roomHandler.sendToSeat(seat, "mapData", {
                mapData = cjson.encode(playerMap:getMap()),
                totalBlocks = totalBlocks,
            })
            
            logic.roomHandler.sendToSeat(seat, "progressUpdate", {
                seat = seat,
                eliminated = 0,
                remaining = totalBlocks,
                percentage = 0,
                finished = 0,
                usedTime = 0,
            })
        end
    end
end

--[[
    START阶段停止：进入PLAYING阶段
]]
function logic.stopStepStart()
    log.info("[Logic] START阶段停止")
    logic.startStep(config.GAME_STEP.PLAYING)
end

--[[
    START阶段超时处理
]]
function logic.onStepStartTimeout()
    log.info("[Logic] START阶段超时，进入PLAYING阶段")
    logic.stopStep(config.GAME_STEP.START)
end

--[[
    ==================== PLAYING 阶段 ====================
]]

--[[
    PLAYING阶段开始：广播阶段ID，允许玩家消除
]]
function logic.startStepPlaying()
    log.info("[Logic] PLAYING阶段开始，玩家可以开始消除")
    
    -- 广播当前阶段给所有玩家
    if logic.roomHandler and logic.roomHandler.sendToAll then
        logic.roomHandler.sendToAll("stepId", {
            step = config.GAME_STEP.PLAYING,
        })
    end
end

--[[
    PLAYING阶段停止：进入END阶段
]]
function logic.stopStepPlaying()
    log.info("[Logic] PLAYING阶段停止")
    logic.startStep(config.GAME_STEP.END)
end

--[[
    PLAYING阶段超时处理（时间到，强制结束）
]]
function logic.onStepPlayingTimeout()
    log.info("[Logic] PLAYING阶段超时，强制结束游戏")
    logicHandler.endGame(config.END_TYPE.TIMEOUT)
end

--[[
    ==================== END 阶段 ====================
]]

--[[
    END阶段开始：广播阶段ID，结算游戏
]]
function logic.startStepEnd()
    log.info("[Logic] END阶段开始")
    
    -- 广播当前阶段给所有玩家
    if logic.roomHandler and logic.roomHandler.sendToAll then
        logic.roomHandler.sendToAll("stepId", {
            step = config.GAME_STEP.END,
        })
    end
end

--[[
    END阶段停止：通知Room游戏结束
]]
function logic.stopStepEnd()
    log.info("[Logic] END阶段停止，游戏结束")
    -- 通知Room本局结束已在endGame中处理
end

--[[
    END阶段超时处理（END阶段时间为0，通常不会触发）
]]
function logic.onStepEndTimeout()
    -- END阶段时间为0，不处理
end

--[[
    ==================== 初始化 & 游戏控制 ====================
]]

--[[
    重置/初始化逻辑模块（每局开始时调用）
    @param rule: table 游戏规则 { playerCnt, mapRows, mapCols, iconTypes }
    @param roomHandler: table Room 提供的回调接口
]]
function logicHandler.init(rule, roomHandler)
    log.info("[Logic] 初始化单局游戏逻辑")
    
    -- 重置所有状态（关键：每局必须完全重置）
    logic.playerMaps = {}
    logic.playerProgress = {}
    logic.startTime = 0
    logic.gameStatus = config.GAME_STATUS.NONE
    logic.stepId = config.GAME_STEP.NONE
    logic.stepBeginTime = 0
    logic.roundNum = 0
    
    logic.rule = rule or {}
    logic.roomHandler = roomHandler
    logic.binit = true
    
    -- 默认地图配置
    logic.rule.mapRows = logic.rule.mapRows or 8
    logic.rule.mapCols = logic.rule.mapCols or 12
    logic.rule.iconTypes = logic.rule.iconTypes or 8
    logic.rule.playerCnt = logic.rule.playerCnt or 2
    logic.rule.maxTime = logic.rule.maxTime or 600  -- 默认10分钟超时
    
    -- 更新PLAYING阶段时间
    config.STEP_TIME_LEN[config.GAME_STEP.PLAYING] = logic.rule.maxTime
    
    log.info("[Logic] 单局初始化完成，玩家数: %d，地图: %dx%d，限时: %d秒",
        logic.rule.playerCnt, logic.rule.mapRows, logic.rule.mapCols, logic.rule.maxTime)
end

--[[
    生成玩家地图
]]
function logic._generatePlayerMaps()
    local rows = logic.rule.mapRows
    local cols = logic.rule.mapCols
    local iconTypes = logic.rule.iconTypes
    local playerCnt = logic.rule.playerCnt
    
    log.info("[Logic] 生成玩家地图，尺寸: %dx%d，图标种类: %d，玩家数: %d", 
        rows, cols, iconTypes, playerCnt)
    
    for seat = 1, playerCnt do
        local mapData = mapGenerator.generate(rows, cols, iconTypes)
        if mapData then
            local playerMap = Map:new()
            playerMap:initMap(mapData)
            logic.playerMaps[seat] = playerMap
            
            -- 初始化玩家进度
            logic.playerProgress[seat] = {
                eliminated = 0,          -- 已消除数量
                startTime = 0,           -- 开始时间
                finishTime = 0,          -- 完成时间
                rank = 0,                -- 排名
                finished = false,        -- 是否完成
            }
        else
            log.error("[Logic] 为座位%d生成地图失败", seat)
        end
    end
end

--[[
    开始一局游戏
    @param roundNum: number 当前局数（由 Room 传入，用于消息下发）
]]
function logicHandler.startGame(roundNum)
    roundNum = roundNum or 1
    logic.roundNum = roundNum
    
    log.info("[Logic] 开始第%d局游戏", roundNum)
    
    if not logic.binit then
        log.error("[Logic] 游戏逻辑未初始化，请先调用 init()")
        return false
    end
    
    logic.playerMaps = {}
    logic.playerProgress = {}
    logic.startTime = os.time()
    logic.gameStatus = config.GAME_STATUS.PLAYING
    logic.stepId = config.GAME_STEP.NONE
    logic.stepBeginTime = 0
    
    if logic.roomHandler and logic.roomHandler.sendToAll then
        logic.roomHandler.sendToAll("gameStart", {
            roundNum = roundNum,
            startTime = logic.startTime,
            brelink = 0,
        })
    end
    
    logic.startStep(config.GAME_STEP.START)
    
    log.info("[Logic] 第%d局游戏开始，玩家数: %d", roundNum, logic.rule.playerCnt)
    return true
end

--[[
    ==================== 玩家操作处理 ====================
]]

--[[
    处理玩家点击消除请求
    @param seat: number 玩家座位
    @param args: table { row1, col1, row2, col2 }
]]
function logicHandler.clickTiles(seat, args)
    -- 检查当前阶段
    if logic.stepId ~= config.GAME_STEP.PLAYING then
        log.warn("[Logic] 当前不在PLAYING阶段，无法消除")
        return
    end
    
    log.info("[Logic] 玩家%d点击消除: (%d,%d) -> (%d,%d)", 
        seat, args.row1, args.col1, args.row2, args.col2)
    
    local playerMap = logic.playerMaps[seat]
    if not playerMap then
        log.warn("[Logic] 座位%d地图未初始化", seat)
        return
    end
    
    local progress = logic.playerProgress[seat]
    if not progress or progress.finished then
        log.warn("[Logic] 座位%d已结束游戏或进度不存在", seat)
        return
    end
    
    -- 解析点击坐标
    local p1 = { row = args.row1, col = args.col1 }
    local p2 = { row = args.row2, col = args.col2 }
    
    -- 验证坐标有效性
    if not playerMap:isValidBlock(p1) or not playerMap:isValidBlock(p2) then
        log.warn("[Logic] 无效的方块坐标")
        if logic.roomHandler and logic.roomHandler.sendToSeat then
            logic.roomHandler.sendToSeat(seat, "clickResult", {
                code = 0,
                msg = "无效的方块坐标",
                eliminated = progress.eliminated,
                remaining = playerMap:getRemainingBlockCount(),
            })
        end
        return
    end
    
    -- 尝试消除
    local success, lines = playerMap:removeTiles(p1, p2)
    if not success then
        log.warn("[Logic] 无法消除这两个方块")
        if logic.roomHandler and logic.roomHandler.sendToSeat then
            logic.roomHandler.sendToSeat(seat, "clickResult", {
                code = 0,
                msg = "无法消除这两个方块",
                eliminated = progress.eliminated,
                remaining = playerMap:getRemainingBlockCount(),
            })
        end
        return
    end
    
    -- 消除成功，更新进度
    progress.eliminated = progress.eliminated + 2
    local remaining = playerMap:getRemainingBlockCount()
    
    log.info("[Logic] 座位%d消除成功，剩余方块: %d", seat, remaining)
    
    -- 发送消除成功消息给该玩家（协议格式与sproto一致）
    if logic.roomHandler and logic.roomHandler.sendToSeat then
        logic.roomHandler.sendToSeat(seat, "tilesRemoved", {
            code = 1,
            p1 = p1,
            p2 = p2,
            lines = lines,
            eliminated = progress.eliminated,
            remaining = remaining,
        })
    end
    
    -- 广播进度更新给所有人（包含完成百分比）
    local totalBlocks = logic.rule.mapRows * logic.rule.mapCols
    local percentage = math.floor((progress.eliminated / totalBlocks) * 100)
    if logic.roomHandler and logic.roomHandler.sendToAll then
        logic.roomHandler.sendToAll("progressUpdate", {
            seat = seat,
            eliminated = progress.eliminated,
            remaining = remaining,
            percentage = percentage,
            finished = progress.finished and 1 or 0,
            usedTime = progress.usedTime or 0,
        })
    end
    
    -- 检查该玩家是否已完成
    if playerMap:isComplete() then
        logic._onPlayerFinish(seat)
    end
end

--[[
    玩家完成本局游戏
    @param seat: number 玩家座位
]]
function logic._onPlayerFinish(seat)
    local progress = logic.playerProgress[seat]
    if not progress or progress.finished then
        return
    end
    
    progress.finished = true
    progress.finishTime = os.time()
    progress.usedTime = progress.finishTime - progress.startTime
    
    log.info("[Logic] 座位%d完成本局，用时: %d秒", seat, progress.usedTime)
    
    -- 计算本局排名
    local rank = 1
    for otherSeat, otherProgress in pairs(logic.playerProgress) do
        if otherSeat ~= seat and otherProgress.finished and otherProgress.finishTime < progress.finishTime then
            rank = rank + 1
        end
    end
    progress.rank = rank
    
    -- 通知 Room
    if logic.roomHandler and logic.roomHandler.onPlayerFinish then
        logic.roomHandler.onPlayerFinish(seat, progress.usedTime, rank)
    end
    
    -- 广播玩家完成消息（协议格式与sproto一致）
    if logic.roomHandler and logic.roomHandler.sendToAll then
        logic.roomHandler.sendToAll("playerFinished", {
            seat = seat,
            usedTime = progress.usedTime,
            rank = rank,
        })
    end
    
    -- 检查本局是否结束
    logic._checkGameEnd()
end

--[[
    检查本局游戏是否结束
]]
function logic._checkGameEnd()
    local allFinished = true
    local totalPlayers = 0
    local finishedPlayers = 0
    
    for seat, progress in pairs(logic.playerProgress) do
        totalPlayers = totalPlayers + 1
        if progress.finished then
            finishedPlayers = finishedPlayers + 1
        else
            allFinished = false
        end
    end
    
    log.info("[Logic] 检查本局结束: %d/%d 已完成", finishedPlayers, totalPlayers)
    
    -- 如果所有人都完成了，结束本局
    if allFinished and totalPlayers > 0 then
        logic.stopStep(config.GAME_STEP.PLAYING)
    end
end

--[[
    ==================== 游戏结束 ====================
]]

--[[
    结束本局游戏
    @param endType: number 结束类型
]]
function logicHandler.endGame(endType)
    if logic.gameStatus == config.GAME_STATUS.END then
        log.warn("[Logic] 本局已结束，跳过")
        return
    end
    
    -- 如果不在END阶段，先切换到END阶段
    if logic.stepId ~= config.GAME_STEP.END then
        logic.startStep(config.GAME_STEP.END)
    end
    
    log.info("[Logic] 本局游戏结束，类型: %d", endType)
    
    logic.gameStatus = config.GAME_STATUS.END
    local endTime = os.time()
    
    -- 计算本局最终排名
    local rankings = {}
    for seat, progress in pairs(logic.playerProgress) do
        if progress.finished then
            table.insert(rankings, {
                seat = seat,
                usedTime = progress.usedTime,
                eliminated = progress.eliminated,
            })
        else
            -- 未完成，用时为-1
            table.insert(rankings, {
                seat = seat,
                usedTime = -1,
                eliminated = progress.eliminated,
            })
        end
    end
    
    -- 按用时排序（用时短的在前）
    table.sort(rankings, function(a, b)
        if a.usedTime == -1 then return false end
        if b.usedTime == -1 then return true end
        return a.usedTime < b.usedTime
    end)
    
    -- 广播游戏结束（协议格式与sproto一致）
    if logic.roomHandler and logic.roomHandler.sendToAll then
        logic.roomHandler.sendToAll("gameEnd", {
            endType = endType,
            rankings = rankings,
        })
        
        -- 广播所有玩家的最终进度
        local totalBlocks = logic.rule.mapRows * logic.rule.mapCols
        for seat, progress in pairs(logic.playerProgress) do
            local remaining = 0
            local playerMap = logic.playerMaps[seat]
            if playerMap then
                remaining = playerMap:getRemainingBlockCount()
            end
            local percentage = math.floor((progress.eliminated / totalBlocks) * 100)
            logic.roomHandler.sendToAll("progressUpdate", {
                seat = seat,
                eliminated = progress.eliminated,
                remaining = remaining,
                percentage = percentage,
                finished = progress.finished and 1 or 0,
                usedTime = progress.usedTime or 0,
            })
        end
    end
    
    -- 通知 Room 本局结束
    if logic.roomHandler and logic.roomHandler.onGameEnd then
        logic.roomHandler.onGameEnd(endType, rankings)
    end
    
    logic.stopStep(config.GAME_STEP.END)
end

--[[
    ==================== 其他功能 ====================
]]

--[[
    玩家重连
    @param seat: number 玩家座位
]]
function logicHandler.relink(seat)
    log.info("[Logic] 座位%d重连", seat)
    
    local playerMap = logic.playerMaps[seat]
    local progress = logic.playerProgress[seat]
    
    if not playerMap or not progress then
        log.warn("[Logic] 座位%d数据不存在，无法重连", seat)
        return
    end
    
    if logic.roomHandler and logic.roomHandler.sendToSeat then
        logic.roomHandler.sendToSeat(seat, "stepId", {
            step = logic.stepId,
        })
        
        logic.roomHandler.sendToSeat(seat, "gameRelink", {
            startTime = logic.startTime,
        })
        
        local totalBlocks = logic.rule.mapRows * logic.rule.mapCols
        logic.roomHandler.sendToSeat(seat, "mapData", {
            mapData = cjson.encode(playerMap:getMap()),
            totalBlocks = totalBlocks,
        })
        
        local percentage = math.floor((progress.eliminated / totalBlocks) * 100)
        logic.roomHandler.sendToSeat(seat, "progressUpdate", {
            seat = seat,
            eliminated = progress.eliminated,
            remaining = playerMap:getRemainingBlockCount(),
            percentage = percentage,
            finished = progress.finished and 1 or 0,
            usedTime = progress.usedTime or 0,
        })
    end
end

--[[
    定时更新（每帧调用，检查阶段超时）
    参考10001实现
]]
function logicHandler.update()
    -- 检查是否初始化
    if not logic.binit then
        return
    end
    
    local stepid = logic.getStepId()
    if stepid == config.GAME_STEP.NONE or stepid == config.GAME_STEP.END then
        return
    end
    
    local currentTime = os.time()
    local timeLen = currentTime - logic.stepBeginTime  -- 计算已进行的时间
    
    -- 如果超过阶段时间限制，触发超时处理
    if timeLen >= logic.getStepTimeLen(stepid) then
        logic.onStepTimeout(stepid)
    end
end

--[[
    获取本局游戏状态
    @return table 游戏状态信息
]]
function logicHandler.getGameStatus()
    return {
        status = logic.gameStatus,
        startTime = logic.startTime,
        stepId = logic.stepId,
        playerProgress = logic.playerProgress,
    }
end

--[[
    获取玩家地图
    @param seat: number 玩家座位
    @return table | nil 地图实例
]]
function logicHandler.getPlayerMap(seat)
    return logic.playerMaps[seat]
end

--[[
    获取本局排名信息（供 Room 统计多局战绩）
    @return table 排名列表
]]
function logicHandler.getRankings()
    local rankings = {}
    for seat, progress in pairs(logic.playerProgress) do
        table.insert(rankings, {
            seat = seat,
            finished = progress.finished,
            usedTime = progress.usedTime or -1,
            eliminated = progress.eliminated,
            rank = progress.rank,
        })
    end
    
    table.sort(rankings, function(a, b)
        if not a.finished then return false end
        if not b.finished then return true end
        return a.usedTime < b.usedTime
    end)
    
    return rankings
end

return logicHandler
