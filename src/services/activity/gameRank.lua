local gameRank = {}
local log = require "log"
local tools = require "activity.tools"

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

    return rankMap
end

function gameRank.getRank(userid)
    local day = os.date("%Y%m%d")
    local rankKey = "game10001DayRank:" .. day
    local rank = tools.callRedis("zrevrank", rankKey, userid)
    return UTILS.result(rank)
end

function gameRank.getRankList()
    local day = os.date("%Y%m%d")
    local rankKey = "game10001DayRank:" .. day
    local rankList = tools.callRedis("zrevrange", rankKey, 0, 19, "withscores")
    return UTILS.result(dealRankList(rankList))
end

return gameRank