local gameRank = {}
local log = require "log"
local tools = require "activity.tools"
local cjson = require "cjson"
local redisRankKey = "game10001RankList"

local function dealRankList(rankList)
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
    tools.callRedis("set", redisRankKey, str, 5 * 60)
    return str
end

local function getRankList()
    local day = os.date("%Y%m%d")
    local rankKey = "game10001DayRank:" .. day
    local rankList = tools.callRedis("zrevrange", rankKey, 0, 19, "withscores")
    return dealRankList(rankList)
end

function gameRank.getRank(userid)
    local day = os.date("%Y%m%d")
    local rankKey = "game10001DayRank:" .. day
    local rank = tools.callRedis("zrevrank", rankKey, userid) or 999999
    log.info("gameRank.getRank userid:%s rank:%s", userid, rank)
    return tools.result(rank)
end

function gameRank.getRankList()
    if not tools.callRedis("exists", redisRankKey) then
        return tools.result(getRankList())
    end

    return tools.result(tools.callRedis("get", redisRankKey))
end

return gameRank