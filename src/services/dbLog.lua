-- dbLog.lua
-- 数据库业务逻辑模块，负责用户认证、数据查询和状态管理等
local skynet = require "skynet"

-- 定义db表，存放所有数据库相关的业务函数
local dbLog = {}

return dbLog