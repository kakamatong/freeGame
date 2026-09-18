-- weekRank.lua
-- 星星周榜的公共周工具：自然周，以东八区（UTC+8）周一 00:00:00 为分界
-- 供 user 服务（写入）与 activity 服务（读取）共用，避免两处各写一份周算法而走偏
local weekRank = {}

local TZ_OFFSET = 8 * 3600        -- 东八区偏移
local DAY_SECONDS = 86400
local WEEK_SECONDS = 7 * DAY_SECONDS

-- 榜单保留时长：2 周
weekRank.KEEP_SECONDS = 14 * DAY_SECONDS

--[[
    计算时间戳所属的自然周序号（东八区，周一为每周第一天）
    算法：epoch 日 0 是 1970-01-01（周四），+3 天后按 7 天取整即对齐到周一
    只使用 os.time() 的 epoch 值并显式加 8 小时，不做任何本地时区换算，
    因此结果不依赖服务器时区设置
    @param {number} ts - 时间戳（os.time()）
    @returns {number} 周序号，连续递增，相邻周相差 1
]]
function weekRank.weekIndex(ts)
    local day = math.floor((ts + TZ_OFFSET) / DAY_SECONDS)
    return math.floor((day + 3) / 7)
end

--[[
    生成周榜 key
    @param {number} gameid - 游戏ID
    @param {number} ts - 时间戳（os.time()）
    @param {number} offset - 周偏移，0=本周，-1=上周
    @returns {string} 形如 game10002WeekStarRank:2960
]]
function weekRank.key(gameid, ts, offset)
    offset = offset or 0
    return "game" .. gameid .. "WeekStarRank:" .. (weekRank.weekIndex(ts) + offset)
end

return weekRank
