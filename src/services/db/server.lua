local skynet = require "skynet"
local mysql = require "skynet.db.mysql"
local redis = require "skynet.db.redis"
local log = require "log"
require "skynet.manager"
local CMD = {}
local name = "db"
local gConfig = CONFIG
local dbs = {

}
local function startMysql()
    if dbs.db or dbs.dbLog then
        log.info("mysql already started")
        return
    end
    local onConnect = function(db)
        dbs.db = db
        log.info("**mysql connected**")
    end

    local mysql_db = mysql.connect({
        host = gConfig.mysql.host,
        port = gConfig.mysql.port,
        user = gConfig.mysql.user,
        password = gConfig.mysql.password,
        database = gConfig.mysql.database,
        on_connect = onConnect,
    })

    

    local onConnectLog = function(db)
        dbs.dbLog = db
    end

    local mysqlLog_db = mysql.connect({
        host = gConfig.mysqlLog.host,
        port = gConfig.mysqlLog.port,
        user = gConfig.mysqlLog.user,
        password = gConfig.mysqlLog.password,
        database = gConfig.mysqlLog.database,
        on_connect = onConnectLog,
    })
end

local function startRedis()
    if dbs.dbRedis then
        log.info("redis already started")
        return
    end
    redis_db = redis.connect({
        host = gConfig.redis.host,
        port = gConfig.redis.port,
        auth = gConfig.redis.auth,
    })

    dbs.dbRedis = redis_db
end

function start()
    startMysql()
    startRedis()
end

function requireModule(moduleName)
    local dbmodule = nil
    local ok, err = pcall(function()
        dbmodule = require(moduleName)
    end)
    if not ok then
        log.error("requireModule %s error %s", moduleName, err)
    end
    return dbmodule
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
        log.info("%s cmd %s %s",name, cmd, subcmd)
        if cmd == "cmd" then
            local f = assert(CMD[subcmd])
            return skynet.ret(skynet.pack(f(...)))
        else
            local db = assert(dbs[cmd])
            local dbmodule = assert(requireModule(cmd))
            local f = assert(dbmodule[subcmd])
            return skynet.ret(skynet.pack(f(db,...)))
        end
    end)

    skynet.register("." .. name)

    start()
end)