-- dbLog.lua
-- 数据库业务逻辑模块，负责用户认证、数据查询和状态管理等
local skynet = require "skynet"
local log = require "log"
-- 定义db表，存放所有数据库相关的业务函数
local dbLog = {}

-- 检查sql结果
local function sqlResult(res)
    if not res then
        log.error("sql error result is nil")
        return false
    end
    if res.badresult then
        log.error("sql error: %s", res.err)
        return false
    end

    return res
end

-- CREATE TABLE `logLogin` (
--   `id` bigint unsigned NOT NULL AUTO_INCREMENT,
--   `userid` bigint NOT NULL,
--   `nickname` varchar(64) NOT NULL,
--   `ip` varchar(50) DEFAULT NULL,
--   `loginType` varchar(32) DEFAULT NULL COMMENT '登入类型（渠道）',
--   `status` tinyint(1) DEFAULT NULL COMMENT '登录状态(0失败 1成功)',
--   `ext` varchar(256) DEFAULT NULL COMMENT '扩展数据',
--   `create_time` datetime DEFAULT CURRENT_TIMESTAMP,
--   PRIMARY KEY (`id`),
--   KEY `idx_user_id` (`userid`),
--   KEY `idx_status` (`status`),
--   KEY `idx_loginType` (`loginType`),
--   KEY `idx_create_time` (`create_time`)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='登录日志表';

function dbLog.insertLoginLog(mysqlLog, ...)
    local userid, nickname, ip, loginType, status, ext = ...
    local sql = string.format("INSERT INTO logLogin (userid, nickname, ip, loginType, status, ext) VALUES (%d, '%s', '%s', '%s', %d, '%s');", userid, nickname, ip, loginType, status, ext)
    local res, err = mysqlLog:query(sql)
    --log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- CREATE TABLE `logAuth` (
--   `id` bigint unsigned NOT NULL AUTO_INCREMENT,
--   `username` varchar(128) NOT NULL,
--   `ip` varchar(50) DEFAULT NULL,
--   `loginType` varchar(32) DEFAULT NULL COMMENT 'auth类型（渠道）',
--   `status` tinyint(1) DEFAULT NULL COMMENT 'auth状态(0失败 1成功)',
--   `ext` varchar(256) DEFAULT NULL COMMENT '扩展数据',
--   `create_time` datetime DEFAULT CURRENT_TIMESTAMP,
--   PRIMARY KEY (`id`),
--   KEY `idx_user_id` (`username`),
--   KEY `idx_status` (`status`),
--   KEY `idx_loginType` (`loginType`),
--   KEY `idx_create_time` (`create_time`)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='认证日志表';

function dbLog.insertAuthLog(mysqlLog, ...)
    local username, ip, loginType, status, ext = ...
    local sql = string.format("INSERT INTO logAuth (username, ip, loginType, status, ext) VALUES ('%s', '%s', '%s', %d, '%s');", username, ip, loginType, status, ext)
    local res, err = mysqlLog:query(sql)
    --log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- CREATE TABLE `logRoom10001` (
--   `id` bigint NOT NULL AUTO_INCREMENT,
--   `type` tinyint DEFAULT '0' COMMENT '0:创建房间,1:销毁房间，2：游戏开始，3：游戏结束',
--   `userid` bigint DEFAULT '0' COMMENT '用户id',
--   `gameid` bigint DEFAULT '0' COMMENT '游戏id',
--   `roomid` bigint DEFAULT '0' COMMENT '房间号',
--   `time` timestamp NOT NULL COMMENT '发生时间',
--   `ext` text COLLATE utf8mb4_unicode_ci COMMENT '扩展数据',
--   PRIMARY KEY (`id`),
--   KEY `idx_time` (`time`),
--   KEY `idx_gameid_roomid` (`gameid`, `roomid`),
--   KEY `idx_userid` (`userid`)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

function dbLog.insertRoomLog(mysqlLog, ...)
    local logtype, userid, gameid, roomid, time, ext = ...
    local sql = string.format("INSERT INTO logRoom10001 (type, userid, gameid, roomid, time, ext) VALUES (%d, %d, %d, %d, '%s', '%s');", logtype, userid, gameid, roomid, time, ext)
    local res, err = mysqlLog:query(sql)
    --log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

return dbLog