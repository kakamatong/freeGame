-- game/preload.lua
-- 全局预加载脚本，初始化全局配置、常量、工具函数、日志、性能统计和错误处理
local skynet = require "skynet"
local cjson = require "cjson"
-- 全局配置
local config = require "gameConfig" or {}
_G.CONFIG = config

-- 全局工具函数
_G.UTILS = {
    -- 深拷贝一个表，防止数据被意外修改
    deepcopy = function(orig)
        local copy
        if type(orig) == 'table' then
            copy = {}
            for orig_key, orig_value in next, orig, nil do
                copy[UTILS.deepcopy(orig_key)] = UTILS.deepcopy(orig_value)
            end
            setmetatable(copy, UTILS.deepcopy(getmetatable(orig)))
        else
            copy = orig
        end
        return copy
    end,
    
    -- 合并两个表，把t2的内容合并到t1
    table_merge = function(t1, t2)
        for k, v in pairs(t2) do
            t1[k] = v
        end
        return t1
    end,
    
    -- 按分隔符分割字符串，返回分割后的表
    string_split = function(str, delimiter)
        local result = {}
        local from = 1
        local delim_from, delim_to = string.find(str, delimiter, from)
        while delim_from do
            table.insert(result, string.sub(str, from, delim_from - 1))
            from = delim_to + 1
            delim_from, delim_to = string.find(str, delimiter, from)
        end
        table.insert(result, string.sub(str, from))
        return result
    end,

    -- 把table序列化成字符串，方便打印调试
    tableToString=function(tbl, indent)
        if not indent then indent = 0 end
        local str = ""
        local indentStr = string.rep("  ", indent)
        
        if type(tbl) ~= "table" then
            return tostring(tbl)
        end
        
        str = str .. "{\n"
        for k, v in pairs(tbl) do
            str = str .. indentStr .. "  [" .. tostring(k) .. "] = "
            if type(v) == "table" then
                str = str .. UTILS.tableToString(v, indent + 1)
            else
                str = str .. tostring(v)
            end
            str = str .. ",\n"
        end
        str = str .. indentStr .. "}"
        
        return str
    end,
}

-- 性能统计相关工具
_G.STAT = {
    -- 计时开始，记录某个操作的起始时间
    timing_start = function(key)
        if not _G.STAT.timers then
            _G.STAT.timers = {}
        end
        _G.STAT.timers[key] = skynet.now()
    end,
    
    -- 计时结束，返回耗时
    timing_end = function(key)
        if not _G.STAT.timers or not _G.STAT.timers[key] then
            return 0
        end
        local cost = skynet.now() - _G.STAT.timers[key]
        _G.STAT.timers[key] = nil
        return cost
    end,
    
    -- 计数器增加
    counter_inc = function(key, value)
        if not _G.STAT.counters then
            _G.STAT.counters = {}
        end
        _G.STAT.counters[key] = (_G.STAT.counters[key] or 0) + (value or 1)
    end,
}
_G.clusterManager = nil
_G.call = function (...)
    if not _G.clusterManager then
        _G.clusterManager = skynet.localname(CONFIG.SVR_NAME.CLUSTER)
    end
    return skynet.call(_G.clusterManager, "lua", "call", ...)
end

_G.send = function (...)
    if not _G.clusterManager then
        _G.clusterManager = skynet.localname(CONFIG.SVR_NAME.CLUSTER)
    end
    skynet.send(_G.clusterManager, "lua", "send", ...)
end

_G.sendTo = function (name, ...)
    if not _G.clusterManager then
        _G.clusterManager = skynet.localname(CONFIG.SVR_NAME.CLUSTER)
    end
    skynet.send(_G.clusterManager, "lua", "sendTo", name, ...)
end