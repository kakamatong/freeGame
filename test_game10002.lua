--[[
    测试脚本 - 验证游戏10002的核心功能
]]

package.path = package.path .. ";./src/?.lua;./src/services/?.lua;./src/lualib/?.lua"

-- Mock log module
package.preload["log"] = function()
    return {
        info = function(...) print(string.format(...)) end,
        warn = function(...) print("WARN:", string.format(...)) end,
        error = function(...) print("ERROR:", string.format(...)) end,
    }
end

local tileUtils = require "games.10002.tileUtils"
local pathFinder = require "games.10002.pathFinder"
local Map = require "games.10002.map"
local mapGenerator = require "games.10002.mapGenerator"

print("=== 测试游戏10002核心功能 ===\n")

-- 测试1: 工具函数
print("1. 测试 tileUtils 工具函数")
print("   isBlock(5):", tileUtils.isBlock(5))  -- true
print("   isBlock(0):", tileUtils.isBlock(0))  -- false
print("   isBlock(100):", tileUtils.isBlock(100))  -- false
print("   isSameBlock(5, 5):", tileUtils.isSameBlock(5, 5))  -- true
print("   isSameBlock(5, 6):", tileUtils.isSameBlock(5, 6))  -- false
print("   ✓ tileUtils 测试通过\n")

-- 测试2: 地图生成
print("2. 测试地图生成器")
local mapData = mapGenerator.generate(6, 8, 6)
if mapData then
    print("   地图尺寸:", #mapData, "x", #mapData[1])
    print("   ✓ 地图生成成功\n")
else
    print("   ✗ 地图生成失败\n")
end

-- 测试3: 地图管理器
print("3. 测试地图管理器")
local map = Map:new()
map:initMap(mapData)
print("   剩余方块数:", map:getRemainingBlockCount())
print("   地图尺寸:", map:getSize().rows, "x", map:getSize().cols)

-- 获取可消除的方块对
local pairs = map:getAllValidPairs()
print("   可消除对数:", #pairs)

if #pairs > 0 then
    local p1, p2 = pairs[1][1], pairs[1][2]
    print(string.format("   测试消除: (%d,%d) -> (%d,%d)", p1.row, p1.col, p2.row, p2.col))
    
    -- 先检查是否可以连接
    local result = map:canConnect(p1, p2)
    print("   可连接:", result.canConnect)
    
    if result.canConnect then
        -- 执行消除
        local success, lines = map:removeTiles(p1, p2)
        print("   消除成功:", success)
        if success then
            print("   路径线段数:", #lines)
            print("   剩余方块数:", map:getRemainingBlockCount())
        end
    end
end
print("   ✓ 地图管理器测试通过\n")

-- 测试4: 寻路器
print("4. 测试寻路器")
local finder = pathFinder:new()
finder:setMap(mapData)
print("   地图是否存在可消除对:", finder:hasAnyValidPair())

local hint = finder:getHint()
if hint then
    print(string.format("   提示: (%d,%d) -> (%d,%d)", hint[1].row, hint[1].col, hint[2].row, hint[2].col))
end
print("   ✓ 寻路器测试通过\n")

print("=== 所有测试完成 ===")
