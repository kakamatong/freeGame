--[[
    mapGenerator.lua
    连连看地图生成器 - 生成可解的地图
]]

local tileUtils = require "games.10002.tileUtils"
local pathFinder = require "games.10002.pathFinder"
local log = require "log"

local mapGenerator = {}

--[[
    生成可解的连连看地图
    @param rows: number 行数
    @param cols: number 列数
    @param iconTypes: number 图标种类数（1-99）
    @return table | nil 生成的地图（二维数组），失败返回nil
]]
function mapGenerator.generate(rows, cols, iconTypes)
    rows = rows or 8
    cols = cols or 12
    iconTypes = iconTypes or 8
    
    -- 确保图标类型在有效范围内
    iconTypes = math.min(iconTypes, 20)
    iconTypes = math.max(iconTypes, 4)
    
    local maxAttempts = 100
    
    for attempt = 1, maxAttempts do
        -- 生成随机地图
        local map = mapGenerator._generateRandomMap(rows, cols, iconTypes)
        
        -- 检查地图是否有解
        if mapGenerator._hasSolution(map) then
            log.info("[MapGenerator] 地图生成成功，尝试次数: %d，尺寸: %dx%d，图标种类: %d", 
                attempt, rows, cols, iconTypes)
            return map
        end
    end
    
    log.error("[MapGenerator] 地图生成失败，尝试%d次后仍未找到可解地图", maxAttempts)
    return nil
end

--[[
    生成随机地图（不保证可解）
    @param rows: number 行数
    @param cols: number 列数
    @param iconTypes: number 图标种类数
    @return table 随机地图
]]
function mapGenerator._generateRandomMap(rows, cols, iconTypes)
    local map = {}
    
    -- 内部可玩区域（去掉外圈）
    local innerRows = rows - 2
    local innerCols = cols - 2
    local totalTiles = innerRows * innerCols
    
    -- 计算每种图标需要的数量（必须是偶数）
    local tilesPerIcon = math.floor(totalTiles / iconTypes)
    -- 确保每种图标数量是偶数
    tilesPerIcon = tilesPerIcon - (tilesPerIcon % 2)
    
    -- 创建图标池
    local iconPool = {}
    for iconType = 1, iconTypes do
        for i = 1, tilesPerIcon do
            table.insert(iconPool, iconType)
        end
    end
    
    -- 填充剩余的格子
    local remainingTiles = totalTiles - (#iconPool)
    while remainingTiles > 0 do
        local randomIcon = math.random(1, iconTypes)
        -- 每次加2保持偶数
        table.insert(iconPool, randomIcon)
        table.insert(iconPool, randomIcon)
        remainingTiles = remainingTiles - 2
    end
    
    -- Fisher-Yates 洗牌算法
    for i = #iconPool, 2, -1 do
        local j = math.random(1, i)
        iconPool[i], iconPool[j] = iconPool[j], iconPool[i]
    end
    
    -- 初始化地图（最外圈为0）
    for row = 1, rows do
        map[row] = {}
        for col = 1, cols do
            map[row][col] = 0
        end
    end
    
    -- 填充内部可玩区域
    local poolIndex = 1
    for row = 2, rows - 1 do
        for col = 2, cols - 1 do
            map[row][col] = iconPool[poolIndex]
            poolIndex = poolIndex + 1
        end
    end
    
    return map
end

--[[
    检查地图是否有解
    @param map: table 地图二维数组
    @return boolean
]]
function mapGenerator._hasSolution(map)
    local finder = pathFinder:new()
    finder:setMap(map)
    return finder:hasAnyValidPair()
end

--[[
    生成带装饰的地图（可选）
    @param rows: number 行数
    @param cols: number 列数
    @param iconTypes: number 图标种类数
    @param decorationPositions: table 装饰位置列表 {{row, col}, ...}
    @param decorationValue: number 装饰值（>=100）
    @return table | nil 生成的地图
]]
function mapGenerator.generateWithDecorations(rows, cols, iconTypes, decorationPositions, decorationValue)
    decorationValue = decorationValue or 100
    
    -- 计算实际需要填充的区域大小
    local decorationCount = decorationPositions and #decorationPositions or 0
    local playableRows = rows
    local playableCols = cols
    
    -- 生成基础地图
    local map = mapGenerator.generate(playableRows, playableCols, iconTypes)
    if not map then
        return nil
    end
    
    -- 如果有装饰位置，扩展地图并添加装饰
    if decorationCount > 0 then
        -- 创建更大的地图来容纳装饰
        local newMap = {}
        for row = 1, rows do
            newMap[row] = {}
            for col = 1, cols do
                newMap[row][col] = 0
            end
        end
        
        -- 复制原地图到中心区域
        local startRow = 1
        local startCol = 1
        for row = 1, playableRows do
            for col = 1, playableCols do
                newMap[startRow + row - 1][startCol + col - 1] = map[row][col]
            end
        end
        
        -- 添加装饰
        for _, pos in ipairs(decorationPositions) do
            if pos.row >= 1 and pos.row <= rows and pos.col >= 1 and pos.col <= cols then
                newMap[pos.row][pos.col] = decorationValue
            end
        end
        
        map = newMap
    end
    
    return map
end

--[[
    验证地图数据的有效性
    @param map: table 地图二维数组
    @return boolean, string 是否有效，错误信息
]]
function mapGenerator.validate(map)
    if not map or #map == 0 then
        return false, "地图为空"
    end
    
    local rows = #map
    local cols = #map[1]
    
    if cols == 0 then
        return false, "地图列为空"
    end
    
    -- 检查每行长度一致
    for row = 1, rows do
        if #map[row] ~= cols then
            return false, string.format("第%d行长度不一致", row)
        end
    end
    
    -- 统计各类方块数量
    local iconCount = {}
    local totalBlocks = 0
    
    for row = 1, rows do
        for col = 1, cols do
            local value = map[row][col]
            if tileUtils.isBlock(value) then
                iconCount[value] = (iconCount[value] or 0) + 1
                totalBlocks = totalBlocks + 1
            end
        end
    end
    
    -- 检查每种图标数量是否为偶数
    for iconType, count in pairs(iconCount) do
        if count % 2 ~= 0 then
            return false, string.format("图标类型%d的数量%d不是偶数", iconType, count)
        end
    end
    
    -- 检查是否有解
    if totalBlocks > 0 and not mapGenerator._hasSolution(map) then
        return false, "地图无解"
    end
    
    return true, "验证通过"
end

return mapGenerator
