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
    @param designMap: table 可选的10x10模板地图（0=空白,1=可消除,9=障碍）
    @return table | nil 生成的地图（二维数组），失败返回nil
]]
function mapGenerator.generate(rows, cols, iconTypes, designMap)
    rows = rows or 10
    cols = cols or 10
    iconTypes = iconTypes or 10
    
    -- 确保图标类型在有效范围内
    iconTypes = math.min(iconTypes, 20)
    iconTypes = math.max(iconTypes, 4)

    -- 设置随机种子，确保每次生成不同
    math.randomseed(os.time() + math.random(1000000))
    
    local maxAttempts = 100
    
    for attempt = 1, maxAttempts do
        -- 生成随机地图
        local map
        if designMap then
            map = mapGenerator._generateFromDesign(designMap, rows, cols, iconTypes)
        else
            map = mapGenerator._generateRandomMap(rows, cols, iconTypes)
        end
        
        -- 检查地图是否有解
        if map and mapGenerator._hasSolution(map) then
            log.info("[MapGenerator] 地图生成成功，尝试次数: %d，尺寸: %dx%d，图标种类: %d", 
                attempt, rows, cols, iconTypes)
            return map
        end
    end
    
    log.error("[MapGenerator] 地图生成失败，尝试%d次后仍未找到可解地图", maxAttempts)
    return nil
end

--[[
    根据设计模板生成地图
    @param designMap: table 10x10模板地图（0=空白,1=可消除,9=障碍）
    @param rows: number 实际行数
    @param cols: number 实际列数
    @param iconTypes: number 图标种类数
    @return table 生成的地图
]]
function mapGenerator._generateFromDesign(designMap, rows, cols, iconTypes)
    local MAP_SIZE = 10
    
    -- 统计需要填充的位置数量
    local fillPositions = {}
    local obstacleCount = 0
    
    for row = 1, MAP_SIZE do
        for col = 1, MAP_SIZE do
            local val = designMap[row][col]
            if val == 1 then
                table.insert(fillPositions, {row = row, col = col})
            elseif val == 9 then
                obstacleCount = obstacleCount + 1
            end
        end
    end
    
    local totalBlocks = #fillPositions
    local totalTiles = totalBlocks + obstacleCount
    
    -- 平均分配图标（每种图标数量尽量接近，差值不超过1）
    local baseCount = math.floor(totalBlocks / iconTypes)
    if baseCount % 2 ~= 0 then
        baseCount = baseCount - 1
    end
    local remainder = totalBlocks - (baseCount * iconTypes)
    local typesWithExtra = remainder / 2
    
    local iconPool = {}
    for iconType = 1, iconTypes do
        local count = baseCount
        if iconType <= typesWithExtra then
            count = count + 2
        end
        for i = 1, count do
            table.insert(iconPool, iconType)
        end
    end
    
    -- Fisher-Yates 洗牌算法（多轮打乱）
    local shuffleRounds = 3
    for round = 1, shuffleRounds do
        for i = #iconPool, 2, -1 do
            local j = math.random(1, i)
            iconPool[i], iconPool[j] = iconPool[j], iconPool[i]
        end
    end
    
    -- 创建地图
    local map = {}
    for row = 1, MAP_SIZE do
        map[row] = {}
        for col = 1, MAP_SIZE do
            map[row][col] = 0
        end
    end
    
    -- 填充可消除方块
    for i, pos in ipairs(fillPositions) do
        map[pos.row][pos.col] = iconPool[i]
    end
    
    -- 填充障碍物
    local decorationValue = 100
    local obstacleIdx = 1
    for row = 1, MAP_SIZE do
        for col = 1, MAP_SIZE do
            if designMap[row][col] == 9 then
                map[row][col] = decorationValue + obstacleIdx
                obstacleIdx = obstacleIdx + 1
            end
        end
    end
    
    return map
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
    local totalTiles = rows * cols
    
    -- 平均分配图标（每种图标数量尽量接近，差值不超过1）
    local baseCount = math.floor(totalTiles / iconTypes)
    if baseCount % 2 ~= 0 then
        baseCount = baseCount - 1
    end
    local remainder = totalTiles - (baseCount * iconTypes)
    local typesWithExtra = remainder / 2
    
    local iconPool = {}
    for iconType = 1, iconTypes do
        local count = baseCount
        if iconType <= typesWithExtra then
            count = count + 2
        end
        for i = 1, count do
            table.insert(iconPool, iconType)
        end
    end
    
    -- Fisher-Yates 洗牌算法（多轮打乱）
    local shuffleRounds = 3
    for round = 1, shuffleRounds do
        for i = #iconPool, 2, -1 do
            local j = math.random(1, i)
            iconPool[i], iconPool[j] = iconPool[j], iconPool[i]
        end
    end
    
    -- 初始化10x10地图（最外圈为0）
    local MAP_SIZE = 10
    for row = 1, MAP_SIZE do
        map[row] = {}
        for col = 1, MAP_SIZE do
            map[row][col] = 0
        end
    end
    
    -- 计算居中起始位置
    local startRow = math.floor((MAP_SIZE - rows) / 2) + 1
    local startCol = math.floor((MAP_SIZE - cols) / 2) + 1
    
    -- 填充可玩区域（居中）
    local poolIndex = 1
    for r = 1, rows do
        for c = 1, cols do
            map[startRow + r - 1][startCol + c - 1] = iconPool[poolIndex]
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
