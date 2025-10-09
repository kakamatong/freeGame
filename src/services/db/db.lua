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
    local sql = string.format("SELECT * FROM %s WHERE username = '%s';",loginType, username)
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
    local userid,status,gameid,roomid,addr,shortRoomid =...
    -- 默认gameid为0，如果有传gameid则用传入的
    local sql = string.format("INSERT INTO userStatus (userid, status, gameid, roomid, addr,shortRoomid) VALUES (%d, %d, %d, %d,'%s',%d) ON DUPLICATE KEY UPDATE status = %d;",userid,status,0,0,addr,shortRoomid,status)
    if gameid and roomid then
        sql = string.format("INSERT INTO userStatus (userid, status, gameid, roomid, addr,shortRoomid) VALUES (%d, %d, %d, %d,'%s',%d) ON DUPLICATE KEY UPDATE status = %d,gameid=%d,roomid=%d,addr='%s',shortRoomid=%d;",userid,status,gameid,roomid,addr,shortRoomid,status,gameid,roomid,addr,shortRoomid)
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

-- 更新用户昵称和头像
function db.updateUserNameAndHeadurl(mysql,...)
    local userid,nickname,headurl =...
    local sql = string.format("UPDATE userData SET nickname = '%s', headurl = '%s' WHERE userid = %d;",nickname,headurl,userid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
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

-- 创建用户认证信息,用户userid分配以auth表为准
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

-- 插入用户登入数据
function db.insertUserLogin(mysql,...)
    local userid, username,password,loginType =...
    local sql = string.format("INSERT INTO %s (username,userid,password) VALUES ('%s',%d,UPPER(MD5('%s')));",loginType, username,userid,password)
    log.info(sql)
    local res, err = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 更新用户登入数据
function db.updateUserLogin(mysql,...)
    local userid, username, loginType =...
    local sql = string.format("UPDATE %s set userid = %d where username = '%s';",loginType, userid, username)
    log.info(sql)
    local res, err = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 注册用户
function db.registerUser(mysql,...)
    local loginType =...
    local newAuth = db.makeAuth(mysql,loginType)
    if not newAuth then
        log.error("makeAuth error")
        return false
    end
    local userid = newAuth.insert_id
    local nickname = string.format("用户%d",userid)
    db.setUserData(mysql,userid,nickname,"",1,"","","0.0.0.0","")
    return userid
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

function db.getUserGameRecords(mysql,...) 
    local userid,gameid =...
    local sql = string.format("SELECT * FROM userGameRecords WHERE userid = %d AND gameid = %d;",userid,gameid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return res[1]
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

-- 获取并分配私有房间短ID
-- 参数: roomid(长房间ID), owner(房主ID)
-- 返回: shortRoomid(成功) 或 nil(失败)
function db.getPrivateShortRommid(mysql, ...)
    local roomid, owner, addr, gameid, rule = ...
    local now = os.time()
    local limitRoomID = 5000 -- 先限制10000条数据，提升性能
    STAT.timing_start("db1")
    -- 开始事务
    mysql:query("START TRANSACTION;")
    
    -- 使用子查询生成随机偏移量，避免单独查询总数
    local sql = string.format(
        "SELECT COUNT(*) AS total FROM privateRoomid WHERE shortRoomid < %d AND status = 0 AND available_at <= %d;",
        limitRoomID, now
    )
    
    local res = mysql:query(sql)
    if not sqlResult(res) or #res == 0 then
        mysql:query("ROLLBACK;")
        log.error("没有可用的私有房间短ID")
        return nil
    end

    local total = res[1].total
    if total == 0 then
        mysql:query("ROLLBACK;")
        log.error("没有可用的私有房间短ID")
        return nil
    end
    local offset = math.random(0, total - 1)

    local sql = string.format(
        "SELECT shortRoomid FROM privateRoomid WHERE shortRoomid < %d AND status = 0 AND available_at <= %d LIMIT 1 OFFSET %d;",
        limitRoomID, now, offset
    )
    res = mysql:query(sql)
    if not sqlResult(res) or #res == 0 then
        mysql:query("ROLLBACK;")
        log.error("没有可用的私有房间短ID")
        return nil
    end

    
    local shortRoomid = res[1].shortRoomid
    
    -- 更新为已分配状态，并记录房间ID和房主
    local updateSql = string.format(
        "UPDATE privateRoomid SET status = 1, roomid = %d, owner = %d, gameid = %d, addr = '%s', rule = '%s', available_at = %d WHERE shortRoomid = %d and status = 0;",
        roomid, owner, gameid, addr, rule, now + CONFIG.PRIVATE_ROOM_SHORTID_TIME, shortRoomid
    )
    log.info(sql)
    local updateRes = mysql:query(updateSql)
    if not sqlResult(updateRes) then
        mysql:query("ROLLBACK;")
        log.error("更新私有房间短ID状态失败")
        return nil
    end

    if updateRes.affected_rows == 0 then
        mysql:query("ROLLBACK;")
        log.error("更新私有房间短ID状态失败")
        return nil
    end
    
    -- 提交事务
    mysql:query("COMMIT;")
    log.info(string.format("成功分配私有房间短ID: %d 到房间: %d 房主: %d", shortRoomid, roomid, owner))
    local dt = STAT.timing_end("db1")
    log.info(string.format("-----------------------db1耗时: %d", dt))
    return shortRoomid
end

-- 根据短房间ID获取长房间ID
function db.getPrivateRoomid(mysql, ...)
    local shortRoomid = ...
    local sql = string.format("SELECT * FROM privateRoomid WHERE shortRoomid = %d;", shortRoomid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return res[1]
end

-- 清除私有房间短ID, 短id在后续规定时间内不能使用
function db.clearPrivateRoomid(mysql, ...)
    local shortRoomid = ...
    local now = os.time()
    local sql = string.format("UPDATE privateRoomid SET status = 0, roomid = 0, owner = 0, gameid = 0, addr = '', rule = '', available_at = %d WHERE shortRoomid = %d AND available_at <= %d;", now + CONFIG.PRIVATE_ROOM_SHORTID_TIME2, shortRoomid, now)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- CREATE TABLE revokeAccount (
--     userid BIGINT NOT NULL COMMENT '用户id',
--     loginType CHAR(64) NOT NULL COMMENT '登入类型',
--     applyTime TIMESTAMP NOT NULL COMMENT '申请时间',
--     revokeTime TIMESTAMP NULL COMMENT '注销时间',
--     status INT DEFAULT 0 COMMENT '状态，默认0,注销成功为1',
--     ext VARCHAR(256) NULL COMMENT '扩展',
--     PRIMARY KEY (userid)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='注销账号表';
-- 添加注销账号
function db.applyRevokeAcc(mysql,...)
    local userid,loginType = ...
    local sql = string.format("INSERT INTO revokeAccount (userid,loginType,applyTime) VALUES (%d,'%s',CURRENT_TIMESTAMP);",userid,loginType,os.time())
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 获取注销账号
function db.getRevokeAcc(mysql,...)
    local userid = ...
    local sql = string.format("SELECT * FROM revokeAccount WHERE userid = %d;",userid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return res[1]
end

-- 删除注销账号
function db.delRevokeAcc(mysql,...)
    local userid = ...
    local sql = string.format("DELETE FROM revokeAccount WHERE userid = %d;",userid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 注销账号
function db.revokeAcc(mysql,...)
    local userid = ...
    local sql = string.format("UPDATE revokeAccount SET status = 1, revokeTime = CURRENT_TIMESTAMP WHERE userid = %d;",userid)
    local res = mysql:query(sql)
    log.info(UTILS.tableToString(res))
    assert(sqlResult(res))
    return true
end

-- 返回db表，供外部调用
return db