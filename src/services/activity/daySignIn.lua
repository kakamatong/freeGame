local daySignIn = {}
local log = require "log"
local cjson = require "cjson"
function daySignIn.test(args)
    log.info("daySignIn.test %s", UTILS.tableToString(args))
    local msg = {}
    msg.code = 1
    msg.info = "daySignIn1"
    local result = {code = 1, result = cjson.encode(msg)}
    return result
end

return daySignIn