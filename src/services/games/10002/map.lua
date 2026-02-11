--[[
    map.lua
    连连看地图管理器 - 每个玩家一个实例
    对应客户端: MapManager.ts
    
    使用方法:
    local Map = require "games.10002.map"
    local playerMap = Map:new()
    playerMap:initMap(mapData)
]]

local tileUtils = require "games.10002.tileUtils"
local pathFinder = require "games.10002.pathFinder"
local log = require "log"

local Map = {}
Map.__index = Map

--[[
    构造函数
    @return table Map实例
]]
function Map:new()
    local obj = {
        _map = {},      -- 地图二维数组
        _rows = 0,      -- 地图行数
        _cols = 0,      -- 地图列数
        _pathFinder = nil,  -- 寻路器实例
    }
    setmetatable(obj, self)
    return obj
end

--[[
    初始化地图
    @param map: table 二维数组地图，值小于100表示可消除方块，大于等于100表示装饰，0表示空
]]
function Map:initMap(map)
    if not map or #map == 0 or not map[1] or #map[1] == 0 then
        log.error("[Map] 地图数据无效")
        return
    end
    
    -- 深拷贝地图数据
    self._map = {}
    for i = 1, #map do
        self._map[i] = {}
        for j = 1, #map[i] do
            self._map[i][j] = map[i][j]
        end
    end
    
    self._rows = #map
    self._cols = #map[1]
    
    -- 初始化寻路器
    self._pathFinder = pathFinder:new()
    self._pathFinder:setMap(self._map)
    
    log.info("[Map] 地图初始化完成，尺寸: %dx%d", self._rows, self._cols)
end

--[[
    获取当前地图的深拷贝
    @return table 地图二维数组的深拷贝
]]
function Map:getMap()
    local copy = {}
    for i = 1, self._rows do
        copy[i] = {}
        for j = 1, self._cols do
            copy[i][j] = self._map[i][j]
        end
    end
    return copy
end

--[[
    获取原始地图引用（只读，不要修改）
    @return table 地图二维数组
]]
function Map:getRawMap()
    return self._map
end

--[[
    获取指定位置的方块值
    @param row: number 行坐标（从1开始）
    @param col: number 列坐标（从1开始）
    @return number 方块值，如果坐标越界返回-1
]]
function Map:getTile(row, col)
    if not self:_isValidPosition(row, col) then
        log.warn("[Map] 坐标越界: (%d, %d)", row, col)
        return -1
    end
    return self._map[row][col]
end

--[[
    更新指定位置的方块
    @param row: number 行坐标
    @param col: number 列坐标
    @param value: number 新的方块值
    @return boolean 是否更新成功
]]
function Map:setTile(row, col, value)
    if not self:_isValidPosition(row, col) then
        log.warn("[Map] 坐标越界，无法更新: (%d, %d)", row, col)
        return false
    end
    
    self._map[row][col] = value
    
    -- 更新寻路器的地图
    if self._pathFinder then
        self._pathFinder:setMap(self._map)
    end
    
    return true
end

--[[
    消除两个方块（将值设为0）
    @param p1: table {row, col} 第一个方块坐标
    @param p2: table {row, col} 第二个方块坐标
    @return boolean 是否消除成功
]]
function Map:removeTiles(p1, p2)
    if not self:_isValidPosition(p1.row, p1.col) or not self:_isValidPosition(p2.row, p2.col) then
        log.warn("[Map] 消除失败，坐标越界")
        return false
    end
    
    local value1 = self._map[p1.row][p1.col]
    local value2 = self._map[p2.row][p2.col]
    
    if not tileUtils.isBlock(value1) or not tileUtils.isBlock(value2) then
        log.warn("[Map] 消除失败，选择的不是可消除方块")
        return false
    end
    
    if value1 ~= value2 then
        log.warn("[Map] 消除失败，两个方块类型不同")
        return false
    end
    
    -- 检查是否可以连接
    local pathResult = self:canConnect(p1, p2)
    if not pathResult.canConnect then
        log.warn("[Map] 消除失败，两个方块无法连接")
        return false
    end
    
    -- 执行消除
    self._map[p1.row][p1.col] = 0
    self._map[p2.row][p2.col] = 0
    
    -- 更新寻路器的地图
    if self._pathFinder then
        self._pathFinder:setMap(self._map)
    end
    
    log.info("[Map] 消除方块: (%d,%d) 和 (%d,%d)", p1.row, p1.col, p2.row, p2.col)
    return true, pathResult.lines
end

--[[
    判断两个方块是否可以连接
    @param p1: table {row, col} 第一个方块坐标
    @param p2: table {row, col} 第二个方块坐标
    @return table {canConnect, lines}
]]
function Map:canConnect(p1, p2)
    if not self._pathFinder then
        log.error("[Map] 寻路器未初始化")
        return { canConnect = false, lines = {} }
    end
    return self._pathFinder:canConnect(p1, p2)
end

--[[
    获取地图尺寸
    @return table {rows, cols} 地图行数和列数
]]
function Map:getSize()
    return {
        rows = self._rows,
        cols = self._cols,
    }
end

--[[
    获取剩余可消除方块数量
    @return number 剩余可消除方块数量
]]
function Map:getRemainingBlockCount()
    local count = 0
    for row = 1, self._rows do
        for col = 1, self._cols do
            if tileUtils.isBlock(self._map[row][col]) then
                count = count + 1
            end
        end
    end
    return count
end

--[[
    获取所有可消除方块的坐标
    @return table 可消除方块的坐标数组 {{row, col}, ...}
]]
function Map:getAllBlocks()
    local blocks = {}
    for row = 1, self._rows do
        for col = 1, self._cols do
            if tileUtils.isBlock(self._map[row][col]) then
                table.insert(blocks, tileUtils.point(row, col))
            end
        end
    end
    return blocks
end

--[[
    获取指定类型的所有方块坐标
    @param tileType: number 方块类型值
    @return table 该类型方块的坐标数组
]]
function Map:getBlocksByType(tileType)
    local blocks = {}
    for row = 1, self._rows do
        for col = 1, self._cols do
            if self._map[row][col] == tileType then
                table.insert(blocks, tileUtils.point(row, col))
            end
        end
    end
    return blocks
end

--[[
    判断指定位置是否为有效的可消除方块
    @param point: table {row, col} 坐标点
    @return boolean
]]
function Map:isValidBlock(point)
    if not self:_isValidPosition(point.row, point.col) then
        return false
    end
    return tileUtils.isBlock(self._map[point.row][point.col])
end

--[[
    判断指定位置是否为空
    @param row: number 行坐标
    @param col: number 列坐标
    @return boolean
]]
function Map:isEmpty(row, col)
    if not self:_isValidPosition(row, col) then
        return false
    end
    return tileUtils.isEmpty(self._map[row][col])
end

--[[
    判断指定位置是否为装饰方块
    @param row: number 行坐标
    @param col: number 列坐标
    @return boolean
]]
function Map:isDecoration(row, col)
    if not self:_isValidPosition(row, col) then
        return false
    end
    return tileUtils.isDecoration(self._map[row][col])
end

--[[
    检查当前地图是否存在可消除的方块对
    @return boolean
]]
function Map:hasAnyValidPair()
    if not self._pathFinder then
        return false
    end
    return self._pathFinder:hasAnyValidPair()
end

--[[
    获取提示：返回一组可消除的方块
    @return table {p1, p2} | nil 可消除的方块对
]]
function Map:getHint()
    if not self._pathFinder then
        return nil
    end
    return self._pathFinder:getHint()
end

--[[
    获取所有可消除的方块对
    @return table 可消除的方块对数组
]]
function Map:getAllValidPairs()
    if not self._pathFinder then
        return {}
    end
    return self._pathFinder:getAllValidPairs()
end

--[[
    检查是否全部消除完成
    @return boolean
]]
function Map:isComplete()
    return self:getRemainingBlockCount() == 0
end

--[[
    重置地图管理器
]]
function Map:reset()
    self._map = {}
    self._rows = 0
    self._cols = 0
    self._pathFinder = nil
    log.info("[Map] 地图管理器已重置")
end

--[[
    检查坐标是否在地图范围内
    @param row: number 行坐标
    @param col: number 列坐标
    @return boolean
]]
function Map:_isValidPosition(row, col)
    return row >= 1 and row <= self._rows and col >= 1 and col <= self._cols
end

return Map
