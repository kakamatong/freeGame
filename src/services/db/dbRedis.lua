local dbRedis = {}
local log = require "log"

function dbRedis.test(redis)
    local res = redis:set("test", "hello")
    log.info(res)

    local res1 = redis:hset("test2", "test1", "hello1")
    log.info(res1)

    local res2 = redis:hget("test2", "test1")
    log.info(res2)
end

return dbRedis