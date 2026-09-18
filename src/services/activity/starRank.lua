-- starRank.lua
-- 星星周榜：统计本周来更新过关卡数据的玩家的星星总量（非增量）
-- 读接口，走 callActivityFunc 通用通道：moduleName = "starRank"
local starRank = {}
local log = require "log"
local tools = require "activity.tools"
local cjson = require "cjson"
local weekRank = require "weekRank"

local TOP_N = 50                 -- 榜单条数
local CACHE_SECONDS = 5 * 60     -- 榜单结果缓存时长，与 gameRank 保持一致
local DEFAULT_GAME_ID = 10002

local function getCacheKey(gameid, weekOffset)
    return "game" .. gameid .. "StarRankList:" .. weekOffset
end

-- 只接受 0（本周）与 -1（上周），其余一律归到本周
local function getWeekOffset(param)
    local offset = param and tonumber(param.weekOffset) or 0
    if offset ~= -1 then
        offset = 0
    end
    return offset
end

-- 拉取并组装榜单（含昵称），结果写入缓存
local function fetchRankList(rankKey, gameid, weekOffset)
    local list = tools.callRedis("zrevrange", rankKey, 0, TOP_N - 1, "withscores")
    local rankMap = {}
    local index = 1
    for i = 1, #list, 2 do
        local uid = list[i]
        local userData = tools.userData(uid)
        rankMap[index] = {
            userid = uid,
            score = list[i + 1],
            nickname = (userData and userData.nickname) or "",
        }
        index = index + 1
    end
    local str = cjson.encode(rankMap)
    tools.callRedis("set", getCacheKey(gameid, weekOffset), str, CACHE_SECONDS)
    return str
end

local function getRankList(gameid, weekOffset)
    local cacheKey = getCacheKey(gameid, weekOffset)
    if tools.callRedis("exists", cacheKey) then
        return tools.callRedis("get", cacheKey)
    end
    local rankKey = weekRank.key(gameid, os.time(), weekOffset)
    log.info("starRank.getRankList rankKey=%s gameid=%s weekOffset=%s", rankKey, tostring(gameid), tostring(weekOffset))
    return fetchRankList(rankKey, gameid, weekOffset)
end

local function getRank(userid, gameid, weekOffset)
    local rankKey = weekRank.key(gameid, os.time(), weekOffset)
    local rank = tools.callRedis("zrevrank", rankKey, userid) or 999999
    log.info("starRank.getRank userid=%s gameid=%s weekOffset=%s rank=%s",
        tostring(userid), tostring(gameid), tostring(weekOffset), tostring(rank))
    return rank
end

--[[
    获取星星周榜（榜单 + 自己的名次）
    入参: userid, param = { gameid = 10002, weekOffset = 0 | -1 }
    返回: { code = 1, result = json{ rank = 自己名次, rankList = json字符串 } }
]]
function starRank.getRankList(userid, param)
    local gameid = param and tonumber(param.gameid) or DEFAULT_GAME_ID
    local weekOffset = getWeekOffset(param)
    local res = {
        rank = getRank(userid, gameid, weekOffset),
        rankList = getRankList(gameid, weekOffset),
    }
    return tools.result(res)
end

--[[
    获取自己的星星周榜名次
    入参: userid, param = { gameid = 10002, weekOffset = 0 | -1 }
    返回: { code = 1, result = 名次数字 }
]]
function starRank.getRank(userid, param)
    local gameid = param and tonumber(param.gameid) or DEFAULT_GAME_ID
    local weekOffset = getWeekOffset(param)
    return tools.result(getRank(userid, gameid, weekOffset))
end

return starRank
