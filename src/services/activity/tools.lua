local tools = {}
local skynet = require "skynet"
local cjson = require "cjson"
local log = require "log"
local sprotoloader = require "sprotoloader"
local host = sprotoloader.load(1):host "package"
local send_request = host:attach(sprotoloader.load(2))
local svrDB = nil
local svrGate = nil
local svrUser = nil

local function sendSvrMsg(userid, typeName, data)
	local pack = send_request(typeName, data, 1)
    skynet.send(svrGate, "lua", "sendSvrMsg", userid, pack)
end

function tools.result(info)
    if info then
        if type(info) == "table" or type(info) == "number" then
            return {code = 1, result = cjson.encode(info)}
        else
            return {code = 1, result = info}
        end
    else
        return {code = 0, result = "调用接口失败"}
    end
end

-- 调用redis
function tools.callRedis(func,...)
    return skynet.call(svrDB, "lua", "dbRedis", func, ...)
end

-- 调用mysql
function tools.callMysql(func,...)
    return skynet.call(svrDB, "lua", "db", func, ...)
end

-- 下发财富变更信息
function tools.reportAward(userid, richTypes, richNums, allRichNums)
    local data = {
        richTypes = richTypes,
        richNums = richNums,
        allRichNums = allRichNums
    }
    sendSvrMsg(userid, "updateRich", data)
end 

function tools.userData(userid)
    return skynet.call(svrUser, "lua", "userData", userid)
end

function tools.start()
    svrGate = skynet.localname(CONFIG.SVR_NAME.GATE)
    svrDB = skynet.localname(CONFIG.SVR_NAME.DB)
    svrUser = skynet.localname(CONFIG.SVR_NAME.USER)
end

return tools