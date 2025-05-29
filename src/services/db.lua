-- db.lua
-- 数据库业务逻辑模块，负责用户认证、数据查询和状态管理等
local skynet = require "skynet"

-- 定义db表，存放所有数据库相关的业务函数
local db = {}

-- 测试函数（预留，暂未实现）
function db.test(mysql,redis,...)
    -- 这里可以写测试数据库连接的代码
end

-- 设置用户认证信息
function db.setAuth(mysql,redis,...)
    -- ... 代表可变参数，这里依次取出userid, secret, subid, strType
    local userid, secret, subid, strType = ...
    -- 构造插入或更新auth表的SQL语句
    local sql = string.format("INSERT INTO auth (userid, secret, subid, type) VALUES (%d, '%s', %d, '%s') ON DUPLICATE KEY UPDATE secret = '%s',type= VALUES(type),subid=subid+1, updated_at = CURRENT_TIMESTAMP;",userid,secret,subid,strType,secret)
    LOG.info(sql) -- 打印SQL语句
    local res = mysql:query(sql) -- 执行SQL
    LOG.info(UTILS.tableToString(res)) -- 打印结果
    if res.err then
        LOG.error("insert auth error: %s", res.err) -- 插入出错
        return false
    end
    -- 返回当前用户的subid
    return db.getAuthSubid(mysql,redis,userid)
end

-- 获取用户的subid
function db.getAuthSubid(mysql,redis,userid)
    local sql = string.format("SELECT subid FROM auth WHERE userid = %d;",userid)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("select auth error: %s", err)
        return false
    end
    if #res == 0 then
        return nil -- 没查到
    end
    return res[1].subid -- 返回subid
end

-- 获取用户认证信息
function db.getAuth(mysql,redis,...)
    local userid = ...
    LOG.info("getAuth:"..userid)
    local sql = string.format("SELECT * FROM auth WHERE userid = %d;",userid)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("select auth error: %s", err)
        return false
    end
    if #res == 0 then
        return nil
    end
    return res[1] -- 返回用户认证信息
end

-- 更新用户secret
function db.doAuth(mysql,redis,...)
    local userid, secret =...
    local sql = string.format("UPDATE auth SET secret = '%s' WHERE userid = %d;",secret,userid)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("update auth error: %s", err)
        return false
    end
    return true
end

-- 检查用户认证信息是否正确
function db.checkAuth(mysql,redis,...)
    local userid, secret =...
    local sql = string.format("SELECT * FROM auth WHERE userid = %d AND secret = '%s';",userid,secret)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("select auth error: %s", err)
        return false
    end
    if #res == 0 then
        return nil -- 没查到
    end
    return res[1] -- 返回认证信息
end

-- 设置用户subid
function db.addSubid(mysql,redis,...)
    local userid, newSubid = ...
    local sql = string.format("UPDATE auth SET subid = %d WHERE userid = %d;",newSubid,userid)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("update auth error: %s", err)
        return false
    end
    return true
end

-- 用户登录校验
function db.login(mysql,redis,...)
    local username,password,loginType = ...
    -- loginType决定查哪个表
    local sql = string.format("SELECT * FROM %s WHERE username = '%s' AND password = UPPER(MD5('%s'));",loginType,username,password)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("select auth error: %s", err)
        return false
    end
    if #res == 0 then
        return nil
    end
    return res[1] -- 返回用户信息
end

-- 获取用户详细数据
function db.getUserData(mysql,redis,...)
    local userid =...
    local sql = string.format("SELECT * FROM userData WHERE userid = %d;",userid)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("select auth error: %s", err)
        return false
    end
    if #res == 0 then
        return nil
    end
    return res[1] -- 返回用户数据
end

-- 获取用户财富信息
function db.getUserRiches(mysql,redis,...)
    local userid =...
    local sql = string.format("SELECT * FROM userRiches WHERE userid = %d;",userid)
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("select auth error: %s", err)
        return false
    end
    if #res == 0 then
        return nil
    end
    return res -- 返回所有财富信息
end

-- 设置用户状态（如在线、离线、在玩哪个游戏）
function db.setUserStatus(mysql,redis,...)
    local userid,status,gameid,roomid =...
    -- 默认gameid为0，如果有传gameid则用传入的
    local sql = string.format("INSERT INTO userStatus (userid, status, gameid, roomid) VALUES (%d, %d, %d, %d) ON DUPLICATE KEY UPDATE status = %d;",userid,status,0,0,status)
    if gameid and roomid then
        sql = string.format("INSERT INTO userStatus (userid, status, gameid, roomid) VALUES (%d, %d, %d, %d) ON DUPLICATE KEY UPDATE status = %d,gameid=%d,roomid=%d;",userid,status,gameid,roomid,status,gameid,roomid)
    end
    local res, err = mysql:query(sql)
    LOG.info(UTILS.tableToString(res))
    if not res or res.badresult then
        LOG.error("setUserStatus error: %s", res.err)
        return false
    end
    return true
end

-- 获取用户状态
function db.getUserStatus(mysql,redis,...)
    local userid =...
    local sql = string.format("SELECT * FROM userStatus WHERE userid = %d;",userid)
    local res, err = mysql:query(sql)
    LOG.info('----------------getUserStatus: %s',sql)
    LOG.info(UTILS.tableToString(res))
    if not res then
        LOG.error("select auth error: %s", err)
        return false
    end
    if #res == 0 then
        return nil
    end
    return res[1] -- 返回用户状态
end

-- 返回db表，供外部调用
return db