-- dbLog.lua
-- 数据库业务逻辑模块，负责用户认证、数据查询和状态管理等
local skynet = require "skynet"

-- 定义db表，存放所有数据库相关的业务函数
local dbLog = {}

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
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("insert logLogin error: %s", err)
        return false
    end
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
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("insert logAuth error: %s", err)
        return false
    end
    return true
end

return dbLog