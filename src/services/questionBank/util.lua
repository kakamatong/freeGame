--[[
    util.lua
    题库服务通用工具：与具体游戏无关，不依赖 skynet，可离线单测
]]

local cjson = require "cjson"

local util = {}

--[[
    读取并解析一个 json 文件
    @param path string 文件路径
    @return table|nil 解析结果
    @return string|nil 错误信息
]]
function util.readJson(path)
    local file = io.open(path, "r")
    if not file then
        return nil, string.format("题库文件不存在: %s", path)
    end
    local content = file:read("*a")
    file:close()
    local ok, data = pcall(cjson.decode, content)
    if not ok or type(data) ~= "table" then
        return nil, string.format("题库文件解析失败: %s", path)
    end
    return data
end

--[[
    把 excludeIds 规整成集合，兼容两种写法：
    - 数组：{"id1", "id2"}
    - 映射：{["id1"] = true}
    @param excludeIds table|nil
    @return table|nil 集合 {[id] = true}
]]
function util.buildExclude(excludeIds)
    if type(excludeIds) ~= "table" then
        return nil
    end
    local exclude = {}
    for k, v in pairs(excludeIds) do
        if v == true and type(k) == "string" then
            exclude[k] = true
        elseif type(v) == "string" then
            exclude[v] = true
        end
    end
    return exclude
end

return util
