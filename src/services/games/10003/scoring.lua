local log = require "log"
local _gameid, _roomid = 0, 0
local function getRoomLogTag()
    return string.format("[%d][%d]", _gameid, _roomid)
end

local ScoringSystem = {}
ScoringSystem.__index = ScoringSystem

function ScoringSystem.new(config)
    local self = setmetatable({}, ScoringSystem)
    self.config = config or {}
    self.initial_score = self.config.initial_score or 1000
    self.min_score = self.config.min_score or 0
    self.unfinished_penalty = self.config.unfinished_penalty or {}
    return self
end

--[[
    根据当前分数查找未完成扣分值
    @param score: number 当前分数
    @return number 扣分值（正数）
]]
function ScoringSystem:getUnfinishedPenalty(score)
    for _, tier in ipairs(self.unfinished_penalty) do
        if not tier.threshold or score < tier.threshold then
            return tier.penalty
        end
    end
    return 0
end

--[[
    匹配模式计分
    完成者: delta = playerCnt - rank + 1
    未完成者: 按分数档位扣分

    @param playerScores: table 玩家当前分数 { [seat] = score }
    @param rankings: table 排名列表 { { seat, rank, ... } }
    @return table { [seat] = { oldScore, newScore, delta, rank, reason } }
]]
function ScoringSystem:calculateMatchScore(playerScores, rankings)
    local results = {}
    local playerCnt = #rankings

    for _, r in ipairs(rankings) do
        local seat = r.seat
        local oldScore = playerScores[seat] or self.initial_score
        local isFinished = r.rank > 0
        local delta = 0

        if isFinished then
            delta = playerCnt - r.rank + 1
        else
            local penalty = self:getUnfinishedPenalty(oldScore)
            delta = -penalty
        end

        local newScore = math.floor(math.max(self.min_score, oldScore + delta))

        results[seat] = {
            oldScore = math.floor(oldScore),
            newScore = newScore,
            delta = delta,
            rank = r.rank,
            reason = isFinished and "finished" or "unfinished"
        }

        log.info("%s [Scoring] 匹配模式 座位%d 分数%d->%d (delta:%d) reason:%s", getRoomLogTag(), seat, oldScore, newScore, delta, isFinished and "finished" or "unfinished")
    end

    return results
end

--[[
    私人房计分
    完成者: score = playerCnt - rank + 1
    未完成者: score = 0

    @param playerCnt: number 游戏人数
    @param rankings: table 排名列表 { { seat, rank, ... } }
    @return table { [seat] = { rank, score, reason } }
]]
function ScoringSystem:calculatePrivateScore(playerCnt, rankings)
    local results = {}

    for _, r in ipairs(rankings) do
        local isFinished = r.rank > 0
        local score = 0

        if isFinished then
            score = playerCnt - r.rank + 1
            if score < 0 then
                score = 0
            end
        end

        results[r.seat] = {
            rank = r.rank,
            score = score,
            reason = isFinished and "finished" or "unfinished"
        }

        log.info("%s [Scoring] 私人房 座位%d 得分%d reason:%s", getRoomLogTag(), r.seat, score, isFinished and "finished" or "unfinished")
    end

    return results
end

-- 设置房间上下文（由 Room 调用）
function ScoringSystem.setGameContext(gameid, roomid)
    _gameid = gameid or 0
    _roomid = roomid or 0
end

return ScoringSystem
