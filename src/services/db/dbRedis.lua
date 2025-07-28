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

function dbRedis.hget(redis, key, field)
    return redis:hget(key, field)
end

function dbRedis.hgetall(redis, key)
    return redis:hgetall(key)
end

function dbRedis.hset(redis, key, ...)
    --log.info("hset %s %s %s", key, field, value)
    return redis:hset(key, ...)
end

function dbRedis.expire(redis, key, expire)
    return redis:expire(key, expire)
end

function dbRedis.set(redis, key, value, expire)
    if expire then
        return redis:set(key, value, "EX", expire)
    else
        return redis:set(key, value)
    end
end

function dbRedis.get(redis, key)
    return redis:get(key)
end

function dbRedis.del(redis, key)
    return redis:del(key)
end

function dbRedis.lock(redis, key, value, expire)
    return redis:set(key, value, "NX", "PX", expire)
end

function dbRedis.unlock(redis, key)
    return redis:del(key)
end

function dbRedis.zadd(redis, key, score, member)
    return redis:zadd(key, score, member)
end

function dbRedis.zscore(redis, key, member)
    return redis:zscore(key, member)
end

function dbRedis.zrevrange(redis, key, start, stop)
    return redis:zrevrange(key, start, stop)
end

function dbRedis.zrevrank(redis, key, member)
    return redis:zrevrank(key, member)
end

return dbRedis