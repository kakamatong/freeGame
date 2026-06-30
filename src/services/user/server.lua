local skynet = require "skynet"
local log = require "log"
local CMD = {}
local dbSvr = nil
require "skynet.manager"
-- 返回结果
-- 获取数据库服务句柄

local function start()
    dbSvr = skynet.localname(CONFIG.SVR_NAME.DB)
end

function CMD.userData(userid)
    log.info("userData userid %d", userid)
    local userData = skynet.call(dbSvr, "lua", "db", "getUserData", userid)
    assert(userData)
    return userData
end

function CMD.userRiches(userid)
    local userRiches = skynet.call(dbSvr, "lua", "db", "getUserRiches", userid)
    if not userRiches then
        return {}, {}
    end
    local richType = {}
    local richNums = {}
    for k, v in pairs(userRiches) do
        table.insert(richType, v.richType)
        table.insert(richNums, v.richNums)
    end

    return richType, richNums
end

function CMD.userStatus(userid)
    local status = skynet.call(dbSvr, "lua", "db", "getUserStatus", userid)
    if not status then
        status = {}
        status.status = CONFIG.USER_STATUS.ONLINE
        status.gameid = 0
        status.roomid = 0
        status.shortRoomid = 0
        status.addr = ""
        status.gatewayUrl = ""
    end
    --assert(status)
    return status
end

function CMD.setUserStatus(userid, status, gameid, roomid, addr, shortRoomid, gatewayUrl)
    assert(userid)
    assert(status)
    skynet.send(dbSvr, "lua", "db", "setUserStatus", userid, status, gameid, roomid, addr, shortRoomid, gatewayUrl)
end

-- 奖励通知
function CMD.awardNotice(userid, awardMessage)
    assert(userid)
    assert(awardMessage)
    return skynet.call(dbSvr, "lua", "db", "insertAwardNotice", userid, awardMessage)
end

-- 获取奖励通知
function CMD.getAwardNotice(userid, time)
    assert(userid)
    if not time then
        -- 最近30天
        time = os.date("%Y-%m-%d 00:00:00", os.time() - 30 * 24 * 60 * 60)
    end
    local res = skynet.call(dbSvr, "lua", "db", "getAwardNotice", userid, time)
    return res
end

-- 设置奖励通知为已读
function CMD.setAwardNoticeRead(id)
    assert(id)
    skynet.send(dbSvr, "lua", "db", "setAwardNoticeRead", id)
end

-- 获取用户游戏记录(输赢平)
function CMD.getUserGameRecords(userid, gameid)
    local res = skynet.call(dbSvr, "lua", "db", "getUserGameRecords", userid, gameid)
    if not res then
        return { win = 0, lose = 0, draw = 0, gameid = gameid }
    end
    return res
end

function CMD.updateUserNameAndHeadurl(userid, nickname, headurl)
    assert(userid)
    assert(nickname)
    assert(headurl)
    skynet.send(dbSvr, "lua", "db", "updateUserNameAndHeadurl", userid, nickname, headurl)
end

-- 用户申请注销账号
function CMD.revokeAcc(userid, loginType)
    assert(userid)
    local res = skynet.call(dbSvr, "lua", "db", "getRevokeAcc", userid)
    if not res then
        if skynet.call(dbSvr, "lua", "db", "applyRevokeAcc", userid, loginType) then
            return { code = 1, msg = "申请成功" }
        else
            return { code = 0, msg = "申请失败" }
        end
    else
        if res.status == 1 then
            return { code = 0, msg = "已经注销" }
        else
            local applyTime = res.applyTime
            local year, month, day, hour, min, sec = applyTime:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")

            -- 转换为时间戳
            local timestamp = os.time({
                year = tonumber(year),
                month = tonumber(month),
                day = tonumber(day),
                hour = tonumber(hour),
                min = tonumber(min),
                sec = tonumber(sec)
            })

            local timeNow = os.time()
            if timeNow - timestamp > CONFIG.REVLKE_DAY * 24 * 3600 then
                -- todo:注销
                if skynet.call(dbSvr, "lua", "db", "revokeAcc", userid) then
                    skynet.send(dbSvr, "lua", "db", "delLoginInfo", userid, res.loginType)
                    return { code = 3, msg = "注销成功" }
                else
                    return { code = 0, msg = "注销失败" }
                end
            else
                return { code = 2, msg = "已申请" }
            end
        end
    end
end

-- 取消申请注销账号
function CMD.cancelRevokeAcc(userid)
    assert(userid)
    local res = skynet.call(dbSvr, "lua", "db", "getRevokeAcc", userid)
    if not res then
        return { code = 0, msg = "取消失败，未申请注销" }
    else
        if res.status == 1 then
            return { code = 0, msg = "已经注销" }
        end

        if skynet.call(dbSvr, "lua", "db", "delRevokeAcc", userid) then
            return { code = 1, msg = "取消成功" }
        else
            return { code = 0, msg = "取消失败" }
        end
    end
end

function CMD.useProps(userid, richType, richNums)
    assert(userid)
    assert(richType)
    assert(richNums)
    local success = skynet.call(dbSvr, "lua", "db", "reduceUserRiches2", userid, richType, richNums)
    if success then
        local remain = skynet.call(dbSvr, "lua", "db", "getUserRichesByType", userid, richType)
        local remainNums = remain and remain.richNums or 0
        return { code = 1, msg = "使用成功", remainNums = remainNums }
    else
        return { code = 0, msg = "道具不足" }
    end
end

--[[
    能量重算（内部辅助函数）
    从DB拉取能量数据 → 初始化/恢复计算 → 写入DB → 返回当前状态
]]
local function recalculateEnergy(userid)
    local RT = CONFIG.RICH_TYPE
    local now = os.time()
    local rate = CONFIG.DEFAULT_RATE
    local defaultEnergy = CONFIG.DEFAULT_ENERGY

    local data = skynet.call(dbSvr, "lua", "db", "getUserRichesByTypes",
        userid, RT.ENERGY_LEFT, RT.ENERGY_ADDITIONAL, RT.ENERGY_MAX, RT.ENERGY_UPDATE_TIME)

    -- 初始化
    if not data or not data[RT.ENERGY_LEFT] then
        skynet.call(dbSvr, "lua", "db", "setUserRichesByTypes", userid, {
            [RT.ENERGY_LEFT]        = defaultEnergy,
            [RT.ENERGY_ADDITIONAL]  = 0,
            [RT.ENERGY_MAX]         = defaultEnergy,
            [RT.ENERGY_UPDATE_TIME] = now,
        })
        return { leftEnergy = defaultEnergy, extraEnergy = 0, maxEnergy = defaultEnergy, updateTime = now, rate = rate }
    end

    local left       = data[RT.ENERGY_LEFT].richNums
    local add        = (data[RT.ENERGY_ADDITIONAL] and data[RT.ENERGY_ADDITIONAL].richNums) or 0
    local max        = (data[RT.ENERGY_MAX] and data[RT.ENERGY_MAX].richNums) or defaultEnergy
    local updateTime = (data[RT.ENERGY_UPDATE_TIME] and data[RT.ENERGY_UPDATE_TIME].richNums) or now

    if left + add >= max then
        if updateTime ~= now then
            skynet.call(dbSvr, "lua", "db", "setUserRichesByTypes", userid, {
                [RT.ENERGY_UPDATE_TIME] = now,
            })
        end
        updateTime = now
    else
        local elapsed   = now - updateTime
        local recovered = math.floor(elapsed * rate / 3600)
        if recovered > 0 then
            local actualRecovered = math.min(recovered, max - left)
            local newLeft         = left + actualRecovered
            local timeConsumed    = math.floor(actualRecovered * 3600 / rate)
            local newUpdateTime   = updateTime + timeConsumed

            skynet.call(dbSvr, "lua", "db", "setUserRichesByTypes", userid, {
                [RT.ENERGY_LEFT]        = newLeft,
                [RT.ENERGY_UPDATE_TIME] = newUpdateTime,
            })

            left = newLeft
            updateTime = newUpdateTime
        end
    end

    return { leftEnergy = left, extraEnergy = add, maxEnergy = max, updateTime = updateTime, rate = rate }
end

--[[
    获取用户能量
    能量系统由4个数据组成（存储在 userRiches 表中）：
      leftEnergy (20001) — 当前剩余能量，随时间自动恢复
      extraEnergy (20002) — 额外能量（任务奖励等外部来源叠加）
      maxEnergy (20003) — 能量上限
      updateTime (20004) — 上次能量刷新时间戳（秒）

    计算逻辑：
      1. 初始化：若 leftEnergy 不存在，写入默认值（leftEnergy=maxEnergy=DEFAULT_ENERGY，extraEnergy=0，updateTime=now）
      2. 已满分支：若 leftEnergy + extraEnergy >= maxEnergy，仅更新 updateTime 为当前时间
      3. 恢复分支：否则根据经过时间计算恢复量
         — 恢复量 = floor(经过秒数 × rate / 3600)，rate 为每小时恢复量
         — 实际恢复量不超过 (maxEnergy - leftEnergy)
         — 小数点部分折算回时间：扣除实际恢复量对应的时间，剩余不足1能量的继续累积
           newUpdateTime = updateTime + floor(实际恢复量 × 3600 / rate)
]]
function CMD.userEnergy(userid)
    assert(userid)
    return recalculateEnergy(userid)
end

--[[
    增减用户能量
    change > 0 加能量，change < 0 扣能量
    操作前先调用 recalculateEnergy 重算当前能量
    加减规则：优先操作 extraEnergy（ENERGY_ADDITIONAL）
      — 加法：直接加到 extraEnergy
      — 减法：先扣 extraEnergy 到 0，剩余从 leftEnergy 扣
      — 减法时若 total(extra + left) < needed，返回能量不足
]]
function CMD.userEnergyChange(userid, change)
    assert(userid)
    assert(change and change ~= 0)

    local RT = CONFIG.RICH_TYPE

    -- 先重算当前能量
    local energy = recalculateEnergy(userid)
    local left = energy.leftEnergy
    local extra = energy.extraEnergy
    local max = energy.maxEnergy

    if change > 0 then
        -- 加法：直接加到 extraEnergy
        extra = extra + change
        skynet.call(dbSvr, "lua", "db", "setUserRichesByTypes", userid, {
            [RT.ENERGY_ADDITIONAL] = extra,
        })
        return {
            code = 1,
            msg = "操作成功",
            leftEnergy = left,
            extraEnergy = extra,
            maxEnergy = max,
            updateTime = energy
                .updateTime,
            rate = energy.rate
        }
    end

    -- 减法分支
    local needed = -change
    if left + extra < needed then
        return { code = 0, msg = "能量不足" }
    end

    if extra >= needed then
        extra = extra - needed
    else
        needed = needed - extra
        extra = 0
        left = left - needed
    end

    skynet.call(dbSvr, "lua", "db", "setUserRichesByTypes", userid, {
        [RT.ENERGY_LEFT]       = left,
        [RT.ENERGY_ADDITIONAL] = extra,
    })

    return {
        code = 1,
        msg = "操作成功",
        leftEnergy = left,
        extraEnergy = extra,
        maxEnergy = max,
        updateTime = energy
            .updateTime,
        rate = energy.rate
    }
end

local function getChallengeData(userid)
    assert(userid)
    local res = skynet.call(dbSvr, "lua", "db", "getChallengeData", userid)
    if not res then
        return { chapter = 0, level = 0 }
    end
    return { chapter = res.chapter, level = res.level }
end

function CMD.getChallengeChapterData(userid, chapter)
    assert(userid)
    assert(chapter)
    local res = skynet.call(dbSvr, "lua", "db", "getChallengeChapter", userid, chapter)
    local curData = getChallengeData(userid)
    return { list = res, chapter = chapter, curChapter = curData.chapter, curLevel = curData.level }
end

function CMD.getChallengeData(userid)
    return getChallengeData(userid)
end

function CMD.updateChallengeLevelData(userid, chapter, level, score, stars)
    assert(userid)
    assert(chapter)
    assert(level)
    skynet.call(dbSvr, "lua", "db", "insertChallengeChapter", userid, chapter, level, 0, stars, score, 1, "")
    return { code = 1 }
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)
    --skynet.register(CONFIG.SVR_NAME.USER)
    start()
end)
