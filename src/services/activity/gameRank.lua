local gameRank = {}
local tools = require "activity.tools"

function gameRank.getRank(userid)
    local day = os.date("%Y%m%d")
    local rankKey = "game10001DayRank:" .. day
    local rank = tools.callRedis("zrevrank", rankKey, userid)
    return UTILS.result(rank)
end

function gameRank.getRankList()
    local day = os.date("%Y%m%d")
    local rankKey = "game10001DayRank:" .. day
    local rankList = tools.callRedis("zrevrange", rankKey, 0, 19)
    return UTILS.result(rankList)
end

return gameRank