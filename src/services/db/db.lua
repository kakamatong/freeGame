-- db.lua
-- 数据库业务逻辑模块，负责用户认证、数据查询和状态管理等
local skynet = require "skynet"
local log = require "log"
-- 定义db表，存放所有数据库相关的业务函数
local db = {}

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

-- 测试函数（预留，暂未实现）
function db.test(mysql,...)
    -- 这里可以写测试数据库连接的代码
end

-- 设置用户认证信息
function db.setAuth(mysql,...)
    -- ... 代表可变参数，这里依次取出userid, secret, subid, strType
    local userid, secret, subid, strType = ...
    -- 构造插入或更新auth表的SQL语句
    local sql = string.format("INSERT INTO auth (userid, secret, subid, type) VALUES (%d, '%s', %d, '%s') ON DUPLICATE KEY UPDATE secret = '%s',type= VALUES(type),subid=subid+1, updated_at = CURRENT_TIMESTAMP;",userid,secret,subid,strType,secret)
    log.info(sql) -- 打印SQL语句
    local res = mysql:query(sql) -- 执行SQL
    log.info(UTILS.tableToString(res)) -- 打印结果
    assert(sqlResult(res))
    -- 返回当前用户的subid
    return db.getAuthSubid(mysql,userid)
end

-- 获取用户的subid
function db.getAuthSubid(mysql,userid)
    local sql = string.format("SELECT subid FROM auth WHERE userid = %d;",userid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    if #res == 0 then
        return nil -- 没查到
    end
    return res[1].subid -- 返回subid
end

-- 获取用户认证信息
function db.getAuth(mysql,...)
    local userid = ...
    log.info("getAuth:"..userid)
    local sql = string.format("SELECT * FROM auth WHERE userid = %d;",userid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    if #res == 0 then
        return nil
    end
    return res[1] -- 返回用户认证信息
end

-- 更新用户secret
function db.doAuth(mysql,...)
    local userid, secret =...
    local sql = string.format("UPDATE auth SET secret = '%s' WHERE userid = %d;",secret,userid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 检查用户认证信息是否正确
function db.checkAuth(mysql,...)
    local userid, secret =...
    local sql = string.format("SELECT * FROM auth WHERE userid = %d AND secret = '%s';",userid,secret)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    if #res == 0 then
        return nil -- 没查到
    end
    return res[1] -- 返回认证信息
end

-- 设置用户subid
function db.addSubid(mysql,...)
    local userid, newSubid = ...
    local sql = string.format("UPDATE auth SET subid = %d WHERE userid = %d;",newSubid,userid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 用户登录校验
function db.login(mysql,...)
    local username,password,loginType = ...
    -- loginType决定查哪个表
    local sql = string.format("SELECT * FROM %s WHERE username = '%s' AND password = UPPER(MD5('%s'));",loginType,username,password)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    if #res == 0 then
        return nil
    end
    return res[1] -- 返回用户信息
end

-- 获取用户登录信息
function db.getLoginInfo(mysql,...)
    local username,loginType = ...
    local sql = string.format("SELECT * FROM %s WHERE username = '%s';",loginType,username)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    if #res == 0 then
        return nil
    end
    return res[1]
end

-- 获取用户详细数据
function db.getUserData(mysql,...)
    local userid =...
    local sql = string.format("SELECT * FROM userData WHERE userid = %d;",userid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    if #res == 0 then
        return nil
    end
    return res[1] -- 返回用户数据
end

-- 获取用户财富信息
function db.getUserRiches(mysql,...)
    local userid =...
    local sql = string.format("SELECT * FROM userRiches WHERE userid = %d;",userid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    if #res == 0 then
        return nil
    end
    return res -- 返回所有财富信息
end

-- 获取用户财富信息，根据类型获取
function db.getUserRichesByType(mysql,...)
    local userid,richType =...
    local sql = string.format("SELECT * FROM userRiches WHERE userid = %d AND richType = %d;",userid,richType)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    if #res == 0 then
        return nil
    end
    return res[1] -- 返回用户财富信息
end

-- 增加用户财富，如果财富类型不存在，则创建财富类型
function db.addUserRiches(mysql,...)
    local userid,richType,richNums =...
    local sql = string.format("INSERT INTO userRiches (userid,richType,richNums) VALUES (%d,%d,%d) ON DUPLICATE KEY UPDATE richNums = richNums + %d;",userid,richType,richNums,richNums)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 减少用户财富,如果不够扣直接扣到0
function db.reduceUserRiches(mysql,...)
    local userid,richType,richNums =...
    local nums = db.getUserRichesByType(mysql,userid,richType)
    if nums.richNums < richNums then
        richNums = nums.richNums
    end
    local sql = string.format("UPDATE userRiches SET richNums = richNums - %d WHERE userid = %d AND richType = %d;",richNums,userid,richType)
    local res, err = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 设置用户状态（如在线、离线、在玩哪个游戏）
function db.setUserStatus(mysql,...)
    local userid,status,gameid,roomid,addr =...
    -- 默认gameid为0，如果有传gameid则用传入的
    local sql = string.format("INSERT INTO userStatus (userid, status, gameid, roomid, addr) VALUES (%d, %d, %d, %d,'%s') ON DUPLICATE KEY UPDATE status = %d;",userid,status,0,0,addr,status)
    if gameid and roomid then
        sql = string.format("INSERT INTO userStatus (userid, status, gameid, roomid, addr) VALUES (%d, %d, %d, %d,'%s') ON DUPLICATE KEY UPDATE status = %d,gameid=%d,roomid=%d,addr='%s';",userid,status,gameid,roomid,addr,status,gameid,roomid,addr)
    end
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 获取用户状态
function db.getUserStatus(mysql,...)
    local userid =...
    local sql = string.format("SELECT * FROM userStatus WHERE userid = %d;",userid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    if #res == 0 then
        return nil
    end
    return res[1] -- 返回用户状态
end

-- 获取机器人列表
function db.getRobots(mysql,...)
    local idbegin,idend =...
    local sql = string.format("SELECT * FROM userData WHERE userid >= %d and userid <= %d;",idbegin,idend)
    local res = mysql:query(sql)
    --log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    
    if #res == 0 then
        return nil
    end
    return res
end

-- 创建用户认证信息
function db.makeAuth(mysql,...)
    local loginType =...
    local sql = string.format("INSERT INTO auth (secret,subid,type) VALUES ('',0,'%s');",loginType)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return res
end

-- 设置用户数据
function db.setUserData(mysql,...)
    local userid,nickname,headurl,sex,province,city,ip,ext =...
    local sql = string.format("INSERT INTO `userData` (`userid`, `nickname`, `headurl`, `sex`, `province`, `city`, `ip`, `ext`) VALUES (%d,'%s','%s',%d,'%s','%s','%s','%s');",userid,nickname,headurl,sex,province,city,ip,ext)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return res
end

-- 注册用户
function db.registerUser(mysql,...)
    local username,password,loginType =...
    local newAuth = db.makeAuth(mysql,loginType)
    if not newAuth then
        log.error("makeAuth error")
        return false
    end

    local userid = newAuth.insert_id
    local sql = string.format("INSERT INTO %s (username,userid,password) VALUES ('%s',%d,UPPER(MD5('%s')));",loginType,username,userid,password)
    log.info(sql)
    local res, err = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    local nickname = string.format("用户%d",userid)
    db.setUserData(mysql,userid,nickname,"",1,"","","0.0.0.0","")
    return res.insert_id
end

-- CREATE TABLE userGameRecords (
--     userid BIGINT NOT NULL,
--     gameid BIGINT NOT NULL,
--     win BIGINT DEFAULT 0,
--     lose BIGINT DEFAULT 0,
--     draw BIGINT DEFAULT 0,
--     escape BIGINT DEFAULT 0,
--     other BIGINT DEFAULT 0,
--     update_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
--     PRIMARY KEY (userid, gameid),
--     INDEX idx_userid (userid)
-- );
function db.insertUserGameRecords(mysql,...)
    local userid,gameid,addType,addNums =...
    local sql = string.format("INSERT INTO userGameRecords (userid,gameid,%s) VALUES (%d,%d,%d) ON DUPLICATE KEY UPDATE %s = %s + %d;",addType,userid,gameid,addNums,addType,addType,addNums)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 奖励通知表
-- CREATE TABLE `awardNotices` (
--   `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键',
--   `userid` bigint DEFAULT '0' COMMENT '用户id',
--   `status` tinyint DEFAULT '0' COMMENT '0:未读 1:已读',
--   `awardMessage` text COMMENT '奖励消息',
--   `create_at` datetime DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
--   `update_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
--   PRIMARY KEY (`id`),
--   KEY `idx_create_at` (`create_at`),
--   KEY `idx_userid` (`userid`),
--   KEY `idx_userid_status` (`userid`, `status`)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='奖励通知表';

function db.insertAwardNotice(mysql,...)
    local userid,awardMessage =...
    local sql = string.format("INSERT INTO awardNotices (userid,status,awardMessage) VALUES (%d,%d,'%s');",userid,0,awardMessage)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return res.insert_id
end

-- 获取奖励通知
function db.getAwardNotice(mysql,...)
    local userid,time =...
    local sql = string.format("SELECT * FROM awardNotices WHERE userid = %d AND status = 0 AND create_at > '%s';",userid,time)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return res
end

function db.setAwardNoticeRead(mysql,...)
    local id =...
    local sql = string.format("UPDATE awardNotices SET status = 1 WHERE id = %d;",id)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 返回db表，供外部调用
return db