#!/usr/bin/env lua

--[[
    投票解散功能测试脚本
    测试私人房间的投票解散功能是否正常工作
]]

local function test_vote_disband_logic()
    print("=== 投票解散功能逻辑测试 ===")
    
    -- 模拟PrivateRoom对象
    local PrivateRoom = {}
    PrivateRoom.__index = PrivateRoom
    
    function PrivateRoom:new()
        local obj = {
            roomInfo = {
                nowPlayerNum = 3,
                playerids = {1001, 1002, 1003},
                gameStatus = 2  -- START状态
            },
            players = {
                [1001] = {userid = 1001, seat = 1},
                [1002] = {userid = 1002, seat = 2}, 
                [1003] = {userid = 1003, seat = 3}
            },
            voteDisbandInfo = {
                inProgress = false,
                voteId = 0,
                initiator = 0,
                reason = "",
                startTime = 0,
                timeLimit = 120,
                votes = {},
                needAgreeCount = 0,
                timer = nil
            },
            config = {
                GAME_STATUS = {START = 2}
            }
        }
        setmetatable(obj, self)
        return obj
    end
    
    function PrivateRoom:isPrivateRoom()
        return true
    end
    
    function PrivateRoom:isRoomStatusStarting()
        return self.roomInfo.gameStatus == self.config.GAME_STATUS.START
    end
    
    function PrivateRoom:generateVoteId()
        return os.time() * 10000 + math.random(1000, 9999)
    end
    
    function PrivateRoom:getVoteAgreeCount()
        local count = 0
        for _, vote in pairs(self.voteDisbandInfo.votes) do
            if vote == 1 then
                count = count + 1
            end
        end
        return count
    end
    
    function PrivateRoom:getVoteRefuseCount()
        local count = 0
        for _, vote in pairs(self.voteDisbandInfo.votes) do
            if vote == 0 then
                count = count + 1
            end
        end
        return count
    end
    
    -- 简化的发起投票方法
    function PrivateRoom:voteDisbandRoom(userid, reason)
        if not self:isPrivateRoom() then
            return {code = 0, msg = "非私人房间不支持投票解散"}
        end
        
        if not self:isRoomStatusStarting() then
            return {code = 0, msg = "游戏未开始，无法发起投票解散"}
        end
        
        if not self.players[userid] then
            return {code = 0, msg = "玩家不在房间中"}
        end
        
        if self.voteDisbandInfo.inProgress then
            return {code = 0, msg = "当前有投票解散正在进行中"}
        end
        
        local voteId = self:generateVoteId()
        local playerCount = self.roomInfo.nowPlayerNum
        local needAgreeCount = math.ceil(playerCount * 0.6)
        
        self.voteDisbandInfo = {
            inProgress = true,
            voteId = voteId,
            initiator = userid,
            reason = reason or "",
            startTime = os.time(),
            timeLimit = 120,
            votes = {[userid] = 1}, -- 发起人自动同意
            needAgreeCount = needAgreeCount,
            timer = nil
        }
        
        return {code = 1, msg = "投票解散发起成功", voteId = voteId}
    end
    
    -- 简化的投票响应方法
    function PrivateRoom:voteDisbandResponse(userid, voteId, agree)
        if not self.voteDisbandInfo.inProgress then
            return {code = 0, msg = "当前没有投票解散进行中"}
        end
        
        if self.voteDisbandInfo.voteId ~= voteId then
            return {code = 0, msg = "投票ID无效"}
        end
        
        if not self.players[userid] then
            return {code = 0, msg = "玩家不在房间中"}
        end
        
        if self.voteDisbandInfo.votes[userid] ~= nil then
            return {code = 0, msg = "已经投过票"}
        end
        
        self.voteDisbandInfo.votes[userid] = agree
        
        -- 检查是否有拒绝票
        if agree == 0 then
            self.voteDisbandInfo.inProgress = false
            return {code = 1, msg = "投票成功", result = "拒绝投票，解散失败"}
        end
        
        -- 检查是否达到同意票数要求
        local agreeCount = self:getVoteAgreeCount()
        if agreeCount >= self.voteDisbandInfo.needAgreeCount then
            self.voteDisbandInfo.inProgress = false
            return {code = 1, msg = "投票成功", result = "投票通过，房间解散"}
        end
        
        return {code = 1, msg = "投票成功", result = "继续等待其他玩家投票"}
    end
    
    -- 开始测试
    local room = PrivateRoom:new()
    
    print("1. 测试发起投票解散")
    local result1 = room:voteDisbandRoom(1001, "测试解散")
    print(string.format("发起投票结果: code=%d, msg=%s", result1.code, result1.msg))
    assert(result1.code == 1, "发起投票应该成功")
    
    local voteId = result1.voteId
    print(string.format("投票ID: %d", voteId))
    print(string.format("需要同意人数: %d (总人数%d的60%%)", room.voteDisbandInfo.needAgreeCount, room.roomInfo.nowPlayerNum))
    
    print("\n2. 测试重复发起投票")
    local result2 = room:voteDisbandRoom(1002, "重复发起")
    print(string.format("重复发起结果: code=%d, msg=%s", result2.code, result2.msg))
    assert(result2.code == 0, "重复发起应该失败")
    
    print("\n3. 测试玩家2同意投票")
    local result3 = room:voteDisbandResponse(1002, voteId, 1)
    print(string.format("玩家2投票结果: code=%d, msg=%s, result=%s", 
        result3.code, result3.msg, result3.result or ""))
    assert(result3.code == 1, "投票应该成功")
    
    local agreeCount = room:getVoteAgreeCount()
    print(string.format("当前同意人数: %d", agreeCount))
    
    if agreeCount >= room.voteDisbandInfo.needAgreeCount then
        print("✓ 投票通过，房间应该解散")
    else
        print(string.format("需要继续等待投票，还需要 %d 人同意", 
            room.voteDisbandInfo.needAgreeCount - agreeCount))
        
        print("\n4. 测试玩家3拒绝投票的情况")
        -- 重置状态测试拒绝情况
        room.voteDisbandInfo.votes = {[1001] = 1}  -- 只有发起人同意
        local result4 = room:voteDisbandResponse(1003, voteId, 0)
        print(string.format("玩家3拒绝投票结果: code=%d, msg=%s, result=%s",
            result4.code, result4.msg, result4.result or ""))
        assert(result4.code == 1, "拒绝投票应该成功")
        assert(not room.voteDisbandInfo.inProgress, "拒绝投票后应该结束投票流程")
    end
    
    print("\n5. 测试错误场景")
    room.voteDisbandInfo.inProgress = false
    local result5 = room:voteDisbandResponse(1001, voteId, 1)
    print(string.format("投票结束后再投票: code=%d, msg=%s", result5.code, result5.msg))
    assert(result5.code == 0, "投票结束后再投票应该失败")
    
    print("\n=== 所有测试通过！ ===")
end

-- 测试60%阈值计算
local function test_vote_threshold()
    print("\n=== 60%阈值计算测试 ===")
    
    local test_cases = {
        {players = 2, expected = 2},  -- 2人房: 2*0.6=1.2 -> 2人
        {players = 3, expected = 2},  -- 3人房: 3*0.6=1.8 -> 2人  
        {players = 4, expected = 3},  -- 4人房: 4*0.6=2.4 -> 3人
        {players = 5, expected = 3},  -- 5人房: 5*0.6=3.0 -> 3人
    }
    
    for _, case in ipairs(test_cases) do
        local actual = math.ceil(case.players * 0.6)
        print(string.format("%d人房间需要%d人同意 (实际计算: %d)", 
            case.players, case.expected, actual))
        assert(actual == case.expected, 
            string.format("计算错误: %d人房间应需要%d人同意，实际计算%d", 
                case.players, case.expected, actual))
    end
    
    print("✓ 60%阈值计算测试通过")
end

-- 运行所有测试
if arg and arg[0] and arg[0]:match("test_vote_disband") then
    math.randomseed(os.time())
    test_vote_threshold()
    test_vote_disband_logic()
    print("\n🎉 投票解散功能测试全部通过！")
end

return {
    test_vote_disband_logic = test_vote_disband_logic,
    test_vote_threshold = test_vote_threshold
}