local skynet = require "skynet"
local log = require "log"

local Snowflake = {}
Snowflake.__index = Snowflake

-- 雪花算法参数
local EPOCH = 1609459200000 -- 2021-01-01 00:00:00 UTC
local NODE_ID_BITS = 10
local SEQUENCE_BITS = 12
local MAX_NODE_ID = (1 << NODE_ID_BITS) - 1
local MAX_SEQUENCE = (1 << SEQUENCE_BITS) - 1

-- 节点ID，需要在不同节点上设置不同的值
local node_id = tonumber(skynet.getenv("nodeid")) or 0

-- 检查节点ID是否合法
if node_id < 0 or node_id > MAX_NODE_ID then
    error(string.format("Node ID must be between 0 and %d", MAX_NODE_ID))
end

local last_timestamp = -1
local sequence = 0

-- 生成雪花ID
function Snowflake.generate()
    local current_timestamp = math.floor(skynet.time() * 1000) -- 毫秒时间戳

    -- 处理时间回拨
    if current_timestamp < last_timestamp then
        log.error("Clock moved backwards. Rejecting requests until %d", last_timestamp)
        -- 这里可以选择等待或者抛出异常
        skynet.sleep((last_timestamp - current_timestamp) * 10) -- 等待到上次时间戳
        current_timestamp = math.floor(skynet.time() * 1000)
    end

    -- 同一毫秒内，序列号自增
    if current_timestamp == last_timestamp then
        sequence = sequence + 1
        if sequence > MAX_SEQUENCE then
            -- 序列号溢出，等待下一毫秒
            skynet.sleep(10)
            current_timestamp = math.floor(skynet.time() * 1000)
            sequence = 0
        end
    else
        sequence = 0
    end

    last_timestamp = current_timestamp

    -- 计算雪花ID
    local id = ((current_timestamp - EPOCH) << (NODE_ID_BITS + SEQUENCE_BITS))
                | (node_id << SEQUENCE_BITS)
                | sequence

    return id
end

return Snowflake