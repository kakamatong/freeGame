local gameRank = {}
local log = require "log"
local tools = require "activity.tools"
local cjson = require "cjson"

local function getDayRankKey(gameid)
    local day = os.date("%Y%m%d")
    return "game" .. gameid .. "DayRank:" .. day
end

local function getCacheRankKey(gameid)
    return "game" .. gameid .. "RankList"
end

local function dealRankList(rankList, gameid)
    local rankMap = {}
    local index = 1
    for i = 1, #rankList, 2 do
        local userid = rankList[i]
        local info = {
            userid = userid,
            score = rankList[i + 1],
        }
        log.info("gameRank.getRank userid:%s score:%s", userid, info.score)
        local userData = tools.userData(userid)
        info.nickname = userData.nickname or ""
        rankMap[index] = info
        index = index + 1
    end
    local str = cjson.encode(rankMap)
    local redisRankKey = getCacheRankKey(gameid)
    tools.callRedis("set", redisRankKey, str, 5 * 60)
    return str
end

local function getRankList(gameid)
    local rankKey = getDayRankKey(gameid)
    local rankList = tools.callRedis("zrevrange", rankKey, 0, 19, "withscores")
    return dealRankList(rankList, gameid)
end

local function getRank(userid, gameid)
    local rankKey = getDayRankKey(gameid)
    local rank = tools.callRedis("zrevrank", rankKey, userid) or 999999
    log.info("gameRank.getRank userid:%s rank:%s", userid, rank)
    return rank
end

function gameRank.getRank(userid, param)
    local gameid = param and param.gameid or 10001
    return tools.result(getRank(userid, gameid))
end

function gameRank.getRankList(userid, param)
    local gameid = param and param.gameid or 10001
    local userRank = getRank(userid, gameid)
    local res = {
        rank = userRank
    }
    local redisRankKey = getCacheRankKey(gameid)
    if not tools.callRedis("exists", redisRankKey) then
        local rankList = getRankList(gameid)
        res.rankList = rankList
    else
        res.rankList = tools.callRedis("get", redisRankKey)
    end

    return tools.result(res)
end

return gameRank