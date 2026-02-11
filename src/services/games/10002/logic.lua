--[[
    logic.lua
    连连看游戏核心逻辑模块 - 单局逻辑
    职责：管理一局游戏的生命周期（地图、消除、胜负）
    通过 roomHandler 与 Room 通信
    
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

-- 暴露给 Room 的接口
local logicHandler = {}

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
    
    logic.rule = rule or {}
    logic.roomHandler = roomHandler
    logic.binit = true
    
    -- 默认地图配置
    logic.rule.mapRows = logic.rule.mapRows or 8
    logic.rule.mapCols = logic.rule.mapCols or 12
    logic.rule.iconTypes = logic.rule.iconTypes or 8
    logic.rule.playerCnt = logic.rule.playerCnt or 2
    
    log.info("[Logic] 单局初始化完成，玩家数: %d，地图: %dx%d",
        logic.rule.playerCnt, logic.rule.mapRows, logic.rule.mapCols)
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
    
    log.info("[Logic] 开始第%d局游戏", roundNum)
    
    if not logic.binit then
        log.error("[Logic] 游戏逻辑未初始化，请先调用 init()")
        return false
    end
    
    -- 重置本局状态（确保上一局的数据不会残留）
    logic.playerMaps = {}
    logic.playerProgress = {}
    logic.startTime = os.time()
    logic.gameStatus = config.GAME_STATUS.PLAYING
    
    -- 生成地图
    logic._generatePlayerMaps()
    
    -- 通知每个玩家游戏开始
    for seat, playerMap in pairs(logic.playerMaps) do
        if logic.playerProgress[seat] then
            logic.playerProgress[seat].startTime = logic.startTime
        end
        
        -- 发送游戏开始消息（协议格式与sproto一致）
        if logic.roomHandler and logic.roomHandler.sendToSeat then
            logic.roomHandler.sendToSeat(seat, "gameStart", {
                roundNum = roundNum,
                startTime = logic.startTime,
                brelink = 0,
                mapData = cjson.encode(playerMap:getMap()),
                totalBlocks = playerMap:getRemainingBlockCount(),
            })
        end
    end
    
    log.info("[Logic] 第%d局游戏开始，玩家数: %d", roundNum, logic.rule.playerCnt)
    return true
end

--[[
    处理玩家点击消除请求
    @param seat: number 玩家座位
    @param args: table { row1, col1, row2, col2 }
]]
function logicHandler.clickTiles(seat, args)
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
        logicHandler.endGame(config.END_TYPE.ALL_FINISHED)
    end
end

--[[
    结束本局游戏
    @param endType: number 结束类型
]]
function logicHandler.endGame(endType)
    if logic.gameStatus == config.GAME_STATUS.END then
        log.warn("[Logic] 本局已结束，跳过")
        return
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
    end
    
    -- 通知 Room 本局结束
    if logic.roomHandler and logic.roomHandler.onGameEnd then
        logic.roomHandler.onGameEnd(endType, rankings)
    end
    
    -- 注意：这里不清理数据，重连时可能需要访问
    -- 新局开始时 Room 会重新调用 init 重置
end

--[[
    请求提示
    @param seat: number 玩家座位
    @return table | nil 提示信息
]]
function logicHandler.requestHint(seat)
    local playerMap = logic.playerMaps[seat]
    if not playerMap then
        return nil
    end
    
    local hint = playerMap:getHint()
    if hint and logic.roomHandler and logic.roomHandler.sendToSeat then
        -- 协议格式与sproto一致
        logic.roomHandler.sendToSeat(seat, "hint", {
            p1 = hint[1],
            p2 = hint[2],
        })
    end
    
    return hint
end

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
    
    -- 发送当前游戏状态（协议格式与sproto一致）
    if logic.roomHandler and logic.roomHandler.sendToSeat then
        logic.roomHandler.sendToSeat(seat, "gameRelink", {
            startTime = logic.startTime,
            mapData = cjson.encode(playerMap:getMap()),
            eliminated = progress.eliminated,
            remaining = playerMap:getRemainingBlockCount(),
            finished = progress.finished and 1 or 0,
            usedTime = progress.usedTime or 0,
        })
    end
end

--[[
    定时更新（每帧调用）
]]
function logicHandler.update()
    -- 检查游戏超时等逻辑
    if logic.gameStatus == config.GAME_STATUS.PLAYING then
        local now = os.time()
        local elapsed = now - logic.startTime
        
        -- 可以在这里添加时间限制逻辑
        -- if elapsed > logic.rule.maxTime then
        --     logicHandler.endGame(config.END_TYPE.TIMEOUT)
        -- end
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
