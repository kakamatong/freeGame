--[[
    pathFinder.lua
    连连看寻路算法 - BFS实现，最多2个转弯
    对应客户端: PathFinder.ts
]]

local tileUtils = require "games.10002.tileUtils"
local log = require "log"

local pathFinder = {}
pathFinder.__index = pathFinder

--[[
    创建新的寻路器实例
    @return table PathFinder实例
]]
function pathFinder:new()
    local obj = {
        _map = {},
        _rows = 0,
        _cols = 0,
        _maxTurns = 2,  -- 最大允许转弯次数
    }
    setmetatable(obj, self)
    return obj
end

--[[
    设置当前地图
    @param map: table 二维数组地图
]]
function pathFinder:setMap(map)
    if not map or #map == 0 or not map[1] or #map[1] == 0 then
        log.error("[PathFinder] 地图数据无效")
        return
    end
    
    -- 深拷贝地图
    self._map = {}
    for i = 1, #map do
        self._map[i] = {}
        for j = 1, #map[i] do
            self._map[i][j] = map[i][j]
        end
    end
    
    self._rows = #map
    self._cols = #map[1]
end

--[[
    核心接口：判断两个方块是否可以消除
    @param p1: table {row, col} 第一个方块坐标
    @param p2: table {row, col} 第二个方块坐标
    @return table {canConnect, lines} 寻路结果
    
    规则：
    1. 两个方块值必须相等且 < 100 且 > 0
    2. 路径最多2个转弯
    3. 路径上不能经过装饰方块（>=100）
]]
function pathFinder:canConnect(p1, p2)
    -- 检查坐标有效性
    if not self:_isValidPosition(p1.row, p1.col) or not self:_isValidPosition(p2.row, p2.col) then
        return { canConnect = false, lines = {} }
    end
    
    -- 不能是同一个点
    if tileUtils.isSamePoint(p1, p2) then
        return { canConnect = false, lines = {} }
    end
    
    -- 获取方块值
    local value1 = self._map[p1.row][p1.col]
    local value2 = self._map[p2.row][p2.col]
    
    -- 检查是否为相同的可消除方块
    if not tileUtils.isSameBlock(value1, value2) then
        return { canConnect = false, lines = {} }
    end
    
    -- 执行BFS寻路
    local path = self:_bfs(p1, p2)
    
    if not path then
        return { canConnect = false, lines = {} }
    end
    
    -- 将路径点转换为线段
    local lines = self:_pathToLines(path)
    
    return {
        canConnect = true,
        lines = lines,
    }
end

--[[
    重要接口：判断当前地图是否存在可消除的方块对
    @return boolean
]]
function pathFinder:hasAnyValidPair()
    -- 按类型收集所有方块
    local blocksByType = {}
    
    for row = 1, self._rows do
        for col = 1, self._cols do
            local value = self._map[row][col]
            if tileUtils.isBlock(value) then
                blocksByType[value] = blocksByType[value] or {}
                table.insert(blocksByType[value], tileUtils.point(row, col))
            end
        end
    end
    
    -- 检查每种类型的方块对
    for _, blocks in pairs(blocksByType) do
        if #blocks >= 2 then
            -- 检查所有可能的配对
            for i = 1, #blocks do
                for j = i + 1, #blocks do
                    local result = self:canConnect(blocks[i], blocks[j])
                    if result.canConnect then
                        return true
                    end
                end
            end
        end
    end
    
    return false
end

--[[
    获取所有可消除的方块对
    @return table 可消除的方块对数组 {{p1, p2}, ...}
]]
function pathFinder:getAllValidPairs()
    local validPairs = {}
    local blocksByType = {}
    
    -- 按类型收集所有方块
    for row = 1, self._rows do
        for col = 1, self._cols do
            local value = self._map[row][col]
            if tileUtils.isBlock(value) then
                blocksByType[value] = blocksByType[value] or {}
                table.insert(blocksByType[value], tileUtils.point(row, col))
            end
        end
    end
    
    -- 检查每种类型的所有配对
    for _, blocks in pairs(blocksByType) do
        if #blocks >= 2 then
            for i = 1, #blocks do
                for j = i + 1, #blocks do
                    local result = self:canConnect(blocks[i], blocks[j])
                    if result.canConnect then
                        table.insert(validPairs, { blocks[i], blocks[j] })
                    end
                end
            end
        end
    end
    
    return validPairs
end

--[[
    获取提示：返回一组可消除的方块
    @return table {p1, p2} | nil 可消除的方块对
]]
function pathFinder:getHint()
    local blocksByType = {}
    
    -- 按类型收集所有方块
    for row = 1, self._rows do
        for col = 1, self._cols do
            local value = self._map[row][col]
            if tileUtils.isBlock(value) then
                blocksByType[value] = blocksByType[value] or {}
                table.insert(blocksByType[value], tileUtils.point(row, col))
            end
        end
    end
    
    -- 查找第一个可消除的配对
    for _, blocks in pairs(blocksByType) do
        if #blocks >= 2 then
            for i = 1, #blocks do
                for j = i + 1, #blocks do
                    local result = self:canConnect(blocks[i], blocks[j])
                    if result.canConnect then
                        return { blocks[i], blocks[j] }
                    end
                end
            end
        end
    end
    
    return nil
end

--[[
    BFS寻路算法（最多2个转弯）
    @param start: table {row, col} 起点
    @param end_: table {row, col} 终点
    @return table | nil 路径点数组（包含起点和终点），失败返回nil
    
    状态: (row, col, direction, turnCount, path)
    direction: 当前方向 (0:上, 1:右, 2:下, 3:左, -1:起点)
    turnCount: 转弯次数
]]
function pathFinder:_bfs(start, end_)
    -- 访问标记数组：visited[row][col][direction] = minTurnCount
    local visited = {}
    for row = 1, self._rows do
        visited[row] = {}
        for col = 1, self._cols do
            visited[row][col] = { math.huge, math.huge, math.huge, math.huge }
        end
    end
    
    local queue = {}
    
    -- 从起点向4个方向初始化
    for dir = 0, 3 do
        local delta = tileUtils.DIRECTION_DELTAS[dir + 1]  -- Lua数组从1开始
        local newRow = start.row + delta.row
        local newCol = start.col + delta.col
        
        -- 检查是否可以移动到该位置
        if self:_canMoveTo(newRow, newCol, end_) then
            local newPath = { tileUtils.clonePoint(start), tileUtils.point(newRow, newCol) }
            table.insert(queue, {
                row = newRow,
                col = newCol,
                direction = dir,
                turnCount = 0,
                path = newPath,
            })
            visited[newRow][newCol][dir + 1] = 0
        end
    end
    
    -- BFS搜索
    local head = 1
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        
        -- 到达终点
        if current.row == end_.row and current.col == end_.col then
            return current.path
        end
        
        -- 向4个方向扩展
        for newDir = 0, 3 do
            local delta = tileUtils.DIRECTION_DELTAS[newDir + 1]
            local newRow = current.row + delta.row
            local newCol = current.col + delta.col
            
            -- 检查是否可以移动到该位置
            if not self:_canMoveTo(newRow, newCol, end_) then
                goto continue
            end
            
            -- 计算新的转弯次数
            local newTurnCount = current.turnCount
            if current.direction ~= tileUtils.DIRECTION.NONE and current.direction ~= newDir then
                newTurnCount = newTurnCount + 1
            end
            
            -- 检查转弯次数是否超过限制
            if newTurnCount > self._maxTurns then
                goto continue
            end
            
            -- 检查是否已经访问过（以更少或相等的转弯次数）
            if visited[newRow][newCol][newDir + 1] <= newTurnCount then
                goto continue
            end
            
            -- 更新访问标记并入队
            visited[newRow][newCol][newDir + 1] = newTurnCount
            local newPath = {}
            for _, p in ipairs(current.path) do
                table.insert(newPath, tileUtils.clonePoint(p))
            end
            table.insert(newPath, tileUtils.point(newRow, newCol))
            
            table.insert(queue, {
                row = newRow,
                col = newCol,
                direction = newDir,
                turnCount = newTurnCount,
                path = newPath,
            })
            
            ::continue::
        end
    end
    
    -- 未找到路径
    return nil
end

--[[
    检查是否可以移动到指定位置
    @param row: number 目标行
    @param col: number 目标列
    @param end_: table {row, col} 终点坐标
    @return boolean
    
    规则：
    1. 必须在地图范围内
    2. 如果是终点，总是可以通过
    3. 否则必须是空格子（0），不能是装饰（>=100）
]]
function pathFinder:_canMoveTo(row, col, end_)
    -- 检查范围
    if not self:_isValidPosition(row, col) then
        return false
    end
    
    -- 如果是终点，可以通过
    if row == end_.row and col == end_.col then
        return true
    end
    
    -- 检查该位置是否可以通过（必须是空的）
    local value = self._map[row][col]
    return tileUtils.isEmpty(value)
end

--[[
    将路径点数组转换为线段数组
    @param path: table 路径点数组
    @return table 线段数组 {{p1, p2}, ...}
    
    算法：遍历路径，当方向改变时创建一条新线段
]]
function pathFinder:_pathToLines(path)
    if #path < 2 then
        return {}
    end
    
    local lines = {}
    local lineStart = path[1]
    
    for i = 2, #path do
        -- 检查是否是最后一个点，或者方向会改变
        local isLastPoint = (i == #path)
        local directionWillChange = false
        
        if not isLastPoint then
            local currentDir = self:_getDirection(path[i - 1], path[i])
            local nextDir = self:_getDirection(path[i], path[i + 1])
            directionWillChange = (currentDir ~= nextDir)
        end
        
        -- 如果是最后一点或方向改变，结束当前线段
        if isLastPoint or directionWillChange then
            table.insert(lines, { lineStart, path[i] })
            lineStart = path[i]
        end
    end
    
    return lines
end

--[[
    获取从p1到p2的方向
    @param p1: table {row, col} 起点
    @param p2: table {row, col} 终点
    @return number 方向枚举值
]]
function pathFinder:_getDirection(p1, p2)
    local dRow = p2.row - p1.row
    local dCol = p2.col - p1.col
    
    if dRow == -1 and dCol == 0 then return tileUtils.DIRECTION.UP end
    if dRow == 1 and dCol == 0 then return tileUtils.DIRECTION.DOWN end
    if dRow == 0 and dCol == 1 then return tileUtils.DIRECTION.RIGHT end
    if dRow == 0 and dCol == -1 then return tileUtils.DIRECTION.LEFT end
    
    return tileUtils.DIRECTION.NONE
end

--[[
    检查坐标是否在地图范围内
    @param row: number 行坐标
    @param col: number 列坐标
    @return boolean
]]
function pathFinder:_isValidPosition(row, col)
    return row >= 1 and row <= self._rows and col >= 1 and col <= self._cols
end

return pathFinder
