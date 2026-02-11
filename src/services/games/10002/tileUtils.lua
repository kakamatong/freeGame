--[[
    tileUtils.lua
    连连看方块类型判断工具
    对应客户端: TileMapData.ts 中的 TileUtils 类
]]

local tileUtils = {}

-- 方向枚举 (对应 DIRECTION)
tileUtils.DIRECTION = {
    UP = 0,
    RIGHT = 1,
    DOWN = 2,
    LEFT = 3,
    NONE = -1,
}

-- 方向偏移量数组 (对应 DIRECTION_DELTAS)
tileUtils.DIRECTION_DELTAS = {
    { row = -1, col = 0 },  -- 上
    { row = 0, col = 1 },   -- 右
    { row = 1, col = 0 },   -- 下
    { row = 0, col = -1 },  -- 左
}

--[[
    判断是否为可消除方块（值在1-99之间）
    @param value: number 方块值
    @return boolean
]]
function tileUtils.isBlock(value)
    return value and value > 0 and value < 100
end

--[[
    判断是否为装饰方块（值大于等于100）
    @param value: number 方块值
    @return boolean
]]
function tileUtils.isDecoration(value)
    return value and value >= 100
end

--[[
    判断是否为空方块（值为0）
    @param value: number 方块值
    @return boolean
]]
function tileUtils.isEmpty(value)
    return value == 0
end

--[[
    判断两个方块是否是相同的可消除方块
    @param value1: number 第一个方块值
    @param value2: number 第二个方块值
    @return boolean
]]
function tileUtils.isSameBlock(value1, value2)
    return tileUtils.isBlock(value1) and tileUtils.isBlock(value2) and value1 == value2
end

--[[
    克隆坐标点
    @param point: table {row, col}
    @return table {row, col}
]]
function tileUtils.clonePoint(point)
    return { row = point.row, col = point.col }
end

--[[
    判断两个坐标点是否相同
    @param p1: table {row, col}
    @param p2: table {row, col}
    @return boolean
]]
function tileUtils.isSamePoint(p1, p2)
    return p1.row == p2.row and p1.col == p2.col
end

--[[
    创建坐标点
    @param row: number 行
    @param col: number 列
    @return table {row, col}
]]
function tileUtils.point(row, col)
    return { row = row, col = col }
end

return tileUtils
