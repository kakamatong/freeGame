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
local gameConfig = require "gameConfig"
local log = require "log"
local cjson = require "cjson"
local Map = require "games.10002.map"
local mapGenerator = require "games.10002.mapGenerator"
local skynet = require "skynet"

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
logic.endType = config.END_TYPE.NONE        -- 游戏结束类型
logic.finishOrder = 0                       -- 完成顺序计数器，用于排名

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
    
    logic.roomHandler.sendToAll("stepId", {
        step = stepid,
    })
    
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
    START阶段开始：广播阶段ID，下发所有玩家的地图数据给所有玩家
]]
function logic.startStepStart()
    log.info("[Logic] START阶段开始")

    logic._generatePlayerMaps()
    
    -- 记录毫秒级开始时间
    local startTimeMs = math.floor(skynet.time() * 1000)
    for seat, playerMap in pairs(logic.playerMaps) do
        if logic.playerProgress[seat] then
            logic.playerProgress[seat].startTime = startTimeMs
        end
    end
    
    -- 广播所有玩家的地图给所有玩家
    for seat, playerMap in pairs(logic.playerMaps) do
        local totalBlocks = playerMap:getRemainingBlockCount()
        logic.roomHandler.sendToAll("mapData", {
            mapData = cjson.encode(playerMap:getMap()),
            totalBlocks = totalBlocks,
            seat = seat,
            col = logic.rule.mapCols,
            row = logic.rule.mapRows,
        })
    end
    
    -- 单独发送每个玩家的初始进度
    for seat, playerMap in pairs(logic.playerMaps) do
        local totalBlocks = playerMap:getRemainingBlockCount()
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
    
    -- 发送倒计时时间给所有玩家
    logic.roomHandler.sendToAll("gameClock", {
        time = config.STEP_TIME_LEN[config.GAME_STEP.PLAYING],
        seat = 0,
    })
end

function logic.stopStepPlaying()
    log.info("[Logic] PLAYING阶段停止")
    logic.startStep(config.GAME_STEP.END)
end

function logic.onStepPlayingTimeout()
    log.info("[Logic] PLAYING阶段超时，强制结束游戏")
    
    if logic._checkAllUnfinished() then
        logic.endType = config.END_TYPE.TIMEOUT
    else
        logic.endType = config.END_TYPE.NORMAL
    end
    logic.stopStep(config.GAME_STEP.PLAYING)
end

--[[
    ==================== END 阶段 ====================
]]

function logic.startStepEnd()
    log.info("[Logic] END阶段开始")
    logicHandler.endGame()
end

--[[
    END阶段停止：通知Room游戏结束
]]
function logic.stopStepEnd()
    log.info("[Logic] END阶段停止，游戏结束")
    logic.stepId = config.GAME_STEP.NONE
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
    logic.finishOrder = 0  -- 重置完成顺序计数器
    
    -- 默认地图配置
    logic.rule.mapRows = logic.rule.mapRows or 8
    logic.rule.mapCols = logic.rule.mapCols or 12
    logic.rule.iconTypes = logic.rule.iconTypes or 8
    logic.rule.playerCnt = logic.rule.playerCnt or 2
    logic.rule.maxTime = logic.rule.maxTime or 120  -- 默认10分钟超时
    logic.rule.designMap = logic.rule.designMap or nil
    
    -- 更新PLAYING阶段时间
    config.STEP_TIME_LEN[config.GAME_STEP.PLAYING] = logic.rule.maxTime
    
    log.info("[Logic] 单局初始化完成，玩家数: %d，地图: %dx%d，限时: %d秒",
        logic.rule.playerCnt, logic.rule.mapRows, logic.rule.mapCols, logic.rule.maxTime)
    
    -- 发送游戏逻辑信息给所有玩家
    logic.roomHandler.sendToAll("logicInfo", {
        playerCnt = logic.rule.playerCnt,
        playingStepTime = logic.rule.maxTime,
        ext = "",
    })
end

--[[
    生成玩家地图
]]
function logic._generatePlayerMaps()
    local rows = logic.rule.mapRows
    local cols = logic.rule.mapCols
    local iconTypes = logic.rule.iconTypes
    local playerCnt = logic.rule.playerCnt
    local designMap = logic.rule.designMap
    
    log.info("[Logic] 生成玩家地图，尺寸: %dx%d，图标种类: %d，玩家数: %d", 
        rows, cols, iconTypes, playerCnt)
    
    -- 生成一张公共地图，所有玩家使用相同的地图
    local mapData = mapGenerator.generate(rows, cols, iconTypes, designMap)
    if not mapData then
        log.error("[Logic] 生成地图失败")
        return
    end
    
    for seat = 1, playerCnt do
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
            comboCount = 0,          -- 当前连击数
            maxCombo = 0,            -- 最大连击数
            lastEliminateTime = 0,   -- 上次消除时间(ms)
        }
    end
end

--[[
    打乱指定玩家的地图
    @param seat: number 玩家座位
    @return table | nil 打乱后的地图数据
]]
function logic._shuffleMap(seat)
    local playerMap = logic.playerMaps[seat]
    if not playerMap then
        log.error("[Logic] 座位%d地图不存在", seat)
        return nil
    end
    
    local mapData = playerMap:getMap()
    local rows = #mapData
    local cols = #mapData[1]
    
    -- 收集可消除方块和装饰物位置
    local blocks = {}
    local decorations = {}
    
    for row = 1, rows do
        for col = 1, cols do
            local value = mapData[row][col]
            if value >= 100 then
                -- 装饰物，记录位置
                table.insert(decorations, {row = row, col = col})
            elseif value > 0 then
                -- 可消除方块
                table.insert(blocks, value)
            end
        end
    end
    
    -- Fisher-Yates 打乱方块
    for i = #blocks, 2, -1 do
        local j = math.random(1, i)
        blocks[i], blocks[j] = blocks[j], blocks[i]
    end
    
    -- 重新填充地图
    local blockIndex = 1
    for row = 1, rows do
        for col = 1, cols do
            local value = mapData[row][col]
            if value >= 100 then
                -- 装饰物位置保持不变
            elseif value > 0 then
                -- 填充打乱后的方块
                if blockIndex <= #blocks then
                    mapData[row][col] = blocks[blockIndex]
                    blockIndex = blockIndex + 1
                else
                    mapData[row][col] = 0
                end
            end
        end
    end
    
    -- 更新地图
    playerMap:initMap(mapData)
    
    log.info("[Logic] 座位%d地图打乱完成，剩余方块数: %d", seat, playerMap:getRemainingBlockCount())
    return mapData
end

--[[
    重新生成指定玩家的地图
    @param seat: number 玩家座位
]]
function logic._regeneratePlayerMap(seat)
    local playerMap = logic.playerMaps[seat]
    if not playerMap then
        log.error("[Logic] 座位%d地图不存在", seat)
        return
    end
    
    local rows = logic.rule.mapRows
    local cols = logic.rule.mapCols
    local iconTypes = logic.rule.iconTypes
    
    local mapData = mapGenerator.generate(rows, cols, iconTypes)
    if not mapData then
        log.error("[Logic] 重新生成地图失败")
        return
    end
    
    playerMap:initMap(mapData)
    
    log.info("[Logic] 座位%d地图重新生成完成", seat)
end

--[[
    使用道具打乱指定玩家的地图
    @param seat: number 玩家座位
    @return table {success, reason} 打乱结果
]]
function logic._shufflePlayerMap(seat)
    log.info("[Logic] 使用道具打乱座位%d的地图", seat)

    local playerMap = logic.playerMaps[seat]
    if not playerMap then
        log.error("[Logic] 座位%d地图不存在", seat)
        return {success = false, reason = "地图不存在"}
    end

    local progress = logic.playerProgress[seat]
    if progress and progress.finished then
        log.warn("[Logic] 座位%d已完成游戏，无法打乱", seat)
        return {success = false, reason = "游戏已完成"}
    end

    if playerMap:isComplete() then
        log.warn("[Logic] 座位%d地图已清空，无法打乱", seat)
        return {success = false, reason = "无方块可打乱"}
    end

    if logic.stepId ~= config.GAME_STEP.PLAYING then
        log.warn("[Logic] 当前不在PLAYING阶段，无法打乱")
        return {success = false, reason = "不在游戏阶段"}
    end

    local maxAttempts = 9
    local solvable = false

    for attempt = 1, maxAttempts do
        log.info("[Logic] 座位%d执行第%d次打乱", seat, attempt)
        local newMapData = logic._shuffleMap(seat)
        if not newMapData then
            log.error("[Logic] 打乱失败")
            break
        end

        solvable = playerMap:hasAnyValidPair()
        if solvable then
            break
        end
    end

    if not solvable then
        log.info("[Logic] 打乱后仍不可消除，重新生成地图")
        logic._regeneratePlayerMap(seat)
        logic._broadcastMapShuffled(seat, 2)
    else
        logic._broadcastMapShuffled(seat, 1)
    end

    logic._broadcastMapData(seat)
    log.info("[Logic] 座位%d地图打乱完成", seat)
    return {success = true, reason = "打乱成功"}
end

--[[
    使用道具自动消除一对可消除方块
    @param seat: number 玩家座位
    @return table {success, reason} 消除结果
]]
function logic._autoRemovePair(seat)
    log.info("[Logic] 使用道具自动消除座位%d的方块", seat)

    local playerMap = logic.playerMaps[seat]
    if not playerMap then
        log.error("[Logic] 座位%d地图不存在", seat)
        return {success = false, reason = "地图不存在"}
    end

    local progress = logic.playerProgress[seat]
    if progress and progress.finished then
        log.warn("[Logic] 座位%d已完成游戏，无法自动消除", seat)
        return {success = false, reason = "游戏已完成"}
    end

    if playerMap:isComplete() then
        log.warn("[Logic] 座位%d地图已清空，无法自动消除", seat)
        return {success = false, reason = "无方块可消除"}
    end

    if logic.stepId ~= config.GAME_STEP.PLAYING then
        log.warn("[Logic] 当前不在PLAYING阶段，无法自动消除")
        return {success = false, reason = "不在游戏阶段"}
    end

    local hint = playerMap:getHint()
    if not hint then
        log.warn("[Logic] 座位%d没有可消除的方块对", seat)
        return {success = false, reason = "无可消除方块"}
    end

    local p1, p2 = hint[1], hint[2]
    local args = {
        row1 = p1.row - 1,
        col1 = p1.col - 1,
        row2 = p2.row - 1,
        col2 = p2.col - 1,
    }

    -- todo:下发消除协议
    local result = logicHandler.clickTiles(seat, args)
    if result and result.code == 1 then
        log.info("[Logic] 座位%d自动消除成功", seat)
        return {success = true, reason = "消除成功"}
    end

    log.error("[Logic] 座位%d自动消除失败: %s", seat, result and result.msg or "未知错误")
    return {success = false, reason = result and result.msg or "消除失败"}
end

--[[
    广播地图打乱通知
    @param seat: number 触发打乱的玩家座位
    @param reason: number 原因 1:打乱 2:重新生成
]]
function logic._broadcastMapShuffled(seat, reason)
    logic.roomHandler.sendToAll("mapShuffled", {
        seat = seat,
        reason = reason,
    })
end

--[[
    下发指定玩家的地图给所有玩家
    @param seat: number 玩家座位
]]
function logic._broadcastMapData(seat)
    local playerMap = logic.playerMaps[seat]
    if not playerMap then
        log.error("[Logic] 座位%d地图不存在", seat)
        return
    end
    
    local totalBlocks = logic.rule.mapRows * logic.rule.mapCols
    logic.roomHandler.sendToAll("mapData", {
        mapData = cjson.encode(playerMap:getMap()),
        totalBlocks = totalBlocks,
        seat = seat,
        col = logic.rule.mapCols,
        row = logic.rule.mapRows,
    })
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
    
    logic.roomHandler.sendToAll("gameStart", {
        roundNum = roundNum,
        startTime = logic.startTime,
        brelink = 0,
    })
    
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
        return {code = 0, msg = "当前不在PLAYING阶段"}
    end
    
    log.info("[Logic] 玩家%d点击消除: (%d,%d) -> (%d,%d)", 
        seat, args.row1, args.col1, args.row2, args.col2)
    
    local playerMap = logic.playerMaps[seat]
    if not playerMap then
        log.warn("[Logic] 座位%d地图未初始化", seat)
        return {code = 0, msg = "地图未初始化"}
    end
    
    local progress = logic.playerProgress[seat]
    if not progress or progress.finished then
        log.warn("[Logic] 座位%d已结束游戏或进度不存在", seat)
        return {code = 0, msg = "已结束游戏或进度不存在"}
    end
    
    -- 解析点击坐标（客户端从0开始，服务端+1）
    local p1 = { row = args.row1 + 1, col = args.col1 + 1 }
    local p2 = { row = args.row2 + 1, col = args.col2 + 1 }
    
    if not playerMap:isValidBlock(p1) or not playerMap:isValidBlock(p2) then
        log.warn("[Logic] 无效的方块坐标")
        return {code = 0, msg = "无效的方块坐标", eliminated = progress.eliminated, remaining = playerMap:getRemainingBlockCount()}
    end
    
    local success, lines = playerMap:removeTiles(p1, p2)
    if not success then
        log.warn("[Logic] 无法消除这两个方块")
        return {code = 0, msg = "无法消除这两个方块", eliminated = progress.eliminated, remaining = playerMap:getRemainingBlockCount()}
    end
    
    progress.eliminated = progress.eliminated + 2
    local remaining = playerMap:getRemainingBlockCount()
    
    log.info("[Logic] 座位%d消除成功，剩余方块: %d", seat, remaining)
    
    -- 连击判定
    local currentTime = math.floor(skynet.time() * 1000)
    local comboTimeWindow = config.COMBO.COMBO_TIME_WINDOW * 1000
    if progress.lastEliminateTime > 0 and (currentTime - progress.lastEliminateTime) < comboTimeWindow then
        progress.comboCount = progress.comboCount + 1
        log.info("[Logic] 座位%d连击成功，当前连击数: %d", seat, progress.comboCount)
    else
        progress.comboCount = 1
        log.info("[Logic] 座位%d连击中断，重新开始，当前连击数: %d", seat, progress.comboCount)
    end
    progress.maxCombo = math.max(progress.maxCombo, progress.comboCount)
    progress.lastEliminateTime = currentTime
    
    -- 发送连击成功协议
    logic.roomHandler.sendToAll("comboSuccess", {
        seat = seat,
        comboCount = progress.comboCount,
        comboTime = currentTime,
        comboDuration = comboTimeWindow,
    })
    
    -- 检查剩余地图是否可消除，如不可消除则打乱（仅在未完成时执行）
    local maxAttempts = 9
    local shuffled = false
    local regenerated = false
    
    if not playerMap:isComplete() then
        for attempt = 1, maxAttempts do
            if playerMap:hasAnyValidPair() then
                break
            end
            
            log.info("[Logic] 座位%d的地图不可消除，执行第%d次打乱", seat, attempt)
            local newMapData = logic._shuffleMap(seat)
            if not newMapData then
                log.error("[Logic] 打乱失败，尝试重新生成地图")
                break
            end
            shuffled = true
        end
        
        -- 如果9次打乱后仍不可消除，重新生成地图
        if not playerMap:hasAnyValidPair() then
            log.info("[Logic] 打乱后仍不可消除，重新生成地图")
            logic._regeneratePlayerMap(seat)
            regenerated = true
        end
        
        -- 广播打乱/重新生成通知
        if regenerated then
            logic._broadcastMapShuffled(seat, 2)
            -- 下发新地图给所有玩家
            logic._broadcastMapData(seat)
        elseif shuffled then
            logic._broadcastMapShuffled(seat, 1)
            -- 下发新地图给所有玩家
            logic._broadcastMapData(seat)
        end
        
        
    end
    
    -- 转换lines格式以匹配sproto协议: {start={row, col}, dest={row, col}}
    local formattedLines = {}
    if lines then
        for _, line in ipairs(lines) do
            table.insert(formattedLines, {
                start = {row = line[1].row - 1, col = line[1].col - 1},
                dest = {row = line[2].row - 1, col = line[2].col - 1}
            })
        end
    end
    
    logic.roomHandler.sendToAll("tilesRemoved", {
        code = 1,
        p1 = {row = p1.row - 1, col = p1.col - 1},
        p2 = {row = p2.row - 1, col = p2.col - 1},
        lines = formattedLines,
        eliminated = progress.eliminated,
        remaining = remaining,
        seat = seat,  -- 标识是哪个玩家的消除操作
    })
    
    local totalBlocks = logic.rule.mapRows * logic.rule.mapCols
    local percentage = math.floor((progress.eliminated / totalBlocks) * 100)
    logic.roomHandler.sendToAll("progressUpdate", {
        seat = seat,
        eliminated = progress.eliminated,
        remaining = remaining,
        percentage = percentage,
        finished = progress.finished and 1 or 0,
        usedTime = progress.usedTime or 0,
    })
    
    -- 检查该玩家是否已完成
    if playerMap:isComplete() then
        logic._onPlayerFinish(seat)
    end
    
    return {code = 1, msg = "消除成功", eliminated = progress.eliminated, remaining = remaining}
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
    progress.finishTime = math.floor(skynet.time() * 1000)
    progress.usedTime = progress.finishTime - progress.startTime
    
    -- 增加完成顺序计数器，根据先后顺序排名
    logic.finishOrder = logic.finishOrder + 1
    progress.rank = logic.finishOrder
    
    log.info("[Logic] 座位%d完成本局，用时: %d毫秒，排名: %d", seat, progress.usedTime, progress.rank)
    
    -- 检查是否是第一个完成（用于设置10秒倒计时）
    local finishedCount = 0
    for _, p in pairs(logic.playerProgress) do
        if p.finished then finishedCount = finishedCount + 1 end
    end
    
    if finishedCount == 1 then
        local endCountdown = logic.rule.endTime or 10
        local elapsed = os.time() - logic.stepBeginTime
        local remaining = config.STEP_TIME_LEN[config.GAME_STEP.PLAYING] - elapsed
        
        if remaining > endCountdown then
            config.STEP_TIME_LEN[config.GAME_STEP.PLAYING] = elapsed + endCountdown
            
            logic.roomHandler.sendToAll("gameClock", {
                time = endCountdown,
                seat = 0,
            })
            log.info("[Logic] 第一个玩家完成，设置%d秒倒计时", endCountdown)
        else
            log.info("[Logic] 第一个玩家完成，剩余时间%d秒不超过倒计时%d秒，不重置", remaining, endCountdown)
        end
    end
    
    logic.roomHandler.onPlayerFinish(seat, progress.usedTime, logic.finishOrder)
    
    logic.roomHandler.sendToAll("playerFinished", {
        seat = seat,
        usedTime = progress.usedTime,
        rank = logic.finishOrder,
    })
    
    -- 检查本局是否结束
    logic._checkGameEnd()
end

--[[
    检查本局游戏是否结束
]]
function logic._checkGameEnd()
    local allFinished, finishedPlayers, totalPlayers = logic._checkAllFinished()
    
    log.info("[Logic] 检查本局结束: %d/%d 已完成", finishedPlayers, totalPlayers)
    
    -- 如果所有人都完成了，结束本局
    if allFinished and totalPlayers > 0 then
        logic.endType = config.END_TYPE.ALL_FINISHED
        logic.stopStep(config.GAME_STEP.PLAYING)
    end
end

--[[
    检查所有玩家是否都完成了
]]
function logic._checkAllFinished()
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

    return allFinished, finishedPlayers, totalPlayers
end

--[[
    检查所有玩家是否都未完成
]]
function logic._checkAllUnfinished()
    local allUnfinished = true
    for seat, progress in pairs(logic.playerProgress) do
        if progress.finished then
            allUnfinished = false
            break
        end
    end
    return allUnfinished
end

--[[
    ==================== 游戏结束 ====================
]]

--[[
    结束本局游戏
    @param endType: number 结束类型
]]
function logicHandler.endGame()
    if logic.gameStatus == config.GAME_STATUS.END then
        log.warn("[Logic] 本局已结束，跳过")
        return
    end
    
    log.info("[Logic] 本局游戏结束，类型: %d", logic.endType)
    
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
                rank = progress.rank,
                maxCombo = progress.maxCombo,
            })
        else
            -- 未完成，用时为-1，排名为0
            table.insert(rankings, {
                seat = seat,
                usedTime = -1,
                eliminated = progress.eliminated,
                rank = 0,
                maxCombo = progress.maxCombo,
            })
        end
    end
    
    -- 调用room计分接口获取分数
    local scores = logic.roomHandler.gameResult(logic.endType, rankings)
    
    -- 发送gameEnd协议（包含分数）
    logic.roomHandler.sendToAll("gameEnd", {
        endType = logic.endType,
        rankings = rankings,
        scores = scores,
    })
    
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
    
    logic.roomHandler.onGameEnd(logic.endType, rankings)
    
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

    -- 开始重连
    logic.roomHandler.sendToSeat(seat, "gameRelink", {
        startTime = logic.startTime,
    })
    
    -- 重连时第一条协议：发送游戏逻辑信息
    logic.roomHandler.sendToSeat(seat, "logicInfo", {
        playerCnt = logic.rule.playerCnt,
        playingStepTime = logic.rule.maxTime,
        ext = "",
    })
    
    logic.roomHandler.sendToSeat(seat, "stepId", {
        step = logic.stepId,
    })
    
    -- 如果是PLAYING阶段，下发剩余时间
    if logic.stepId == config.GAME_STEP.PLAYING then
        local elapsed = os.time() - logic.stepBeginTime
        local totalTime = config.STEP_TIME_LEN[config.GAME_STEP.PLAYING]
        local remainingTime = totalTime - elapsed
        
        if remainingTime > 0 then
            logic.roomHandler.sendToSeat(seat, "gameClock", {
                time = remainingTime,
                seat = 0,
            })
            log.info("[Logic] 座位%d重连，PLAYING阶段剩余时间:%d秒", seat, remainingTime)
        end
    end
    
    -- 发送所有玩家的地图给重连玩家
    local totalBlocks = logic.rule.mapRows * logic.rule.mapCols
    for targetSeat, targetMap in pairs(logic.playerMaps) do
        logic.roomHandler.sendToSeat(seat, "mapData", {
            mapData = cjson.encode(targetMap:getMap()),
            totalBlocks = totalBlocks,
            seat = targetSeat,
            col = logic.rule.mapCols,
            row = logic.rule.mapRows,
        })
    end
    
    local percentage = math.floor((progress.eliminated / totalBlocks) * 100)
    logic.roomHandler.sendToSeat(seat, "progressUpdate", {
        seat = seat,
        eliminated = progress.eliminated,
        remaining = playerMap:getRemainingBlockCount(),
        percentage = percentage,
        finished = progress.finished and 1 or 0,
        usedTime = progress.usedTime or 0,
    })
    
    -- 下发房间内已完成玩家的finishInfo
    for targetSeat, targetProgress in pairs(logic.playerProgress) do
        if targetProgress.finished then
            logic.roomHandler.sendToSeat(seat, "playerFinished", {
                seat = targetSeat,
                usedTime = targetProgress.usedTime,
                rank = targetProgress.rank,
            })
            log.info("[Logic] 重连下发座位%d的完成信息，排名%d", targetSeat, targetProgress.rank)
        end
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

--[[
    使用道具统一入口
    @param seat: number 玩家座位
    @param itemId: number 道具ID
    @return table {success, reason}
]]
function logicHandler.useItem(seat, itemId)
    if itemId == gameConfig.RICH_TYPE.UPSET then
        return logic._shufflePlayerMap(seat)
    elseif itemId == gameConfig.RICH_TYPE.AUTO_REMOVE then
        return logic._autoRemovePair(seat)
    end
    return {success = false, reason = "无效的道具ID"}
end

return logicHandler
