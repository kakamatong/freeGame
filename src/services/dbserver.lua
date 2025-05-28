local skynet = require "skynet"
local mysql = require "skynet.db.mysql"
local redis = require "skynet.db.redis"
require "skynet.manager"
local CMD = {}
local FUNC = require "db" or {}
local name = "dbserver"
local mysql_db = nil
local redis_db = nil

local function startMysql()
    if mysql_db then
        LOG.info("mysql already started")
        return
    end
    local onConnect = function(db)
        LOG.info("**mysql connected**")
    end

    mysql_db = mysql.connect({
        host = CONFIG.mysql.host,
        port = CONFIG.mysql.port,
        user = CONFIG.mysql.user,
        password = CONFIG.mysql.password,
        database = CONFIG.mysql.database,
        on_connect = onConnect,
    })
end

local function startRedis()
    if redis_db then
        LOG.info("redis already started")
        return
    end
    redis_db = redis.connect({
        host = CONFIG.redis.host,
        port = CONFIG.redis.port,
        auth = CONFIG.redis.auth,
    })
end

function CMD.start()
    startMysql()
    startRedis()
end

function CMD.stop()
    if mysql_db then
        mysql_db:disconnect()
        mysql_db = nil
    end
    if redis_db then
        redis_db:disconnect()
        redis_db = nil
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        LOG.info("%s cmd %s %s",name, cmd, subcmd)
        if cmd == "func" then
            if not mysql_db or not redis_db then
                LOG.error("mysql or redis not started")
                return skynet.ret(skynet.pack(nil))
            end
            local f = assert(FUNC[subcmd])
            return skynet.ret(skynet.pack(f(mysql_db,redis_db,...)))
        elseif cmd == "cmd" then
            local f = assert(CMD[subcmd])
            return skynet.ret(skynet.pack(f(...)))
        else
            return skynet.ret(skynet.pack(nil))
        end
    end)

    skynet.register("." .. name)
end)