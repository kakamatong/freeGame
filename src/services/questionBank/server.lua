--[[
    server.lua
    题库服务(questionBank)入口
    职责：
    1. 启动时按 games/registry.lua 加载各游戏题库
    2. 对外接口按 gameid 分发到对应游戏模块（games/<gameid>.lua）
    接口约定（服务间调用，经 clusterManager 负载均衡）：
    - getQuestion(gameid, difficultyId, opts) -> {code=1, data=<游戏自定义table>} 或 {code=0, msg=...}
    - getInfo(gameid)                         -> {code=1, data=<游戏自定义table>} 或 {code=0, msg=...}
    - status()                                -> {code=1, data={加载状态}}
    - reload(gameid?)                         -> 重新加载题库
    说明：data 的结构完全由各游戏模块决定，本服务不解释、不加工；
    不同游戏的题库格式各不相同，各自在 games/<gameid>.lua 里解析。
    错误策略：题库加载失败不阻塞服务启动，相关接口返回 code=0 + msg，
    便于调用方回退到自身兜底逻辑，并保留排查信息。
]]

local skynet = require "skynet"
local log = require "log"
local loader = require "questionBank.loader"
local registry = require "questionBank.games.registry"
require "skynet.manager"

local CMD = {}

-- 题库上下文
local g_ctx = nil

--[[
    题库根目录：优先读全局配置，未配置时用模块默认值
    @return string 题库根目录
]]
local function getDataRoot()
    if CONFIG and CONFIG.QUESTION_BANK and CONFIG.QUESTION_BANK.path then
        return CONFIG.QUESTION_BANK.path
    end
    return loader.DEFAULT_DATA_ROOT
end

--[[
    建立上下文并加载题库（失败只记录，不阻塞启动）
]]
local function loadBank()
    g_ctx = loader.new(getDataRoot(), registry)
    g_ctx:preload()

    local okCount = 0
    for _ in pairs(g_ctx.games) do
        okCount = okCount + 1
    end
    local errCount = 0
    for gameid, msg in pairs(g_ctx.errors) do
        errCount = errCount + 1
        log.error("[questionBank] 游戏 %s 题库加载失败: %s", tostring(gameid), tostring(msg))
    end
    log.info("[questionBank] 题库加载完成 dataRoot=%s 成功游戏数=%d 失败数=%d",
        tostring(g_ctx.dataRoot), okCount, errCount)
end

--[[
    取游戏条目并校验其实现了指定方法
    @return table|nil 游戏条目  @return string|nil 错误信息
]]
local function requireGame(gameid, methodName)
    if not g_ctx then
        return nil, "题库未加载"
    end
    local game, err = g_ctx:get(gameid)
    if not game then
        return nil, err
    end
    if type(game.module[methodName]) ~= "function" then
        return nil, string.format("游戏 %s 未实现接口: %s", tostring(gameid), tostring(methodName))
    end
    return game, nil
end

--[[
    按 gameid + 难度id 取一道题目
    @param gameid number 游戏id
    @param difficultyId number 难度id
    @param opts table|nil 取题选项（结构由各游戏模块自行约定，常见为 mode / excludeIds）
    @return table {code, data|msg}
]]
function CMD.getQuestion(gameid, difficultyId, opts)
    local game, err = requireGame(gameid, "pick")
    if not game then
        return { code = 0, msg = err }
    end
    if not tonumber(difficultyId) then
        return { code = 0, msg = "参数错误: difficultyId 必须为数字" }
    end

    local data, pickErr = game.module.pick(game.state, difficultyId, opts)
    if not data then
        return { code = 0, msg = pickErr }
    end
    return { code = 1, data = data }
end

--[[
    取游戏题库信息（结构由各游戏模块决定）
    @return table {code, data|msg}
]]
function CMD.getInfo(gameid)
    local game, err = requireGame(gameid, "info")
    if not game then
        return { code = 0, msg = err }
    end
    local data, infoErr = game.module.info(game.state)
    if not data then
        return { code = 0, msg = infoErr }
    end
    return { code = 1, data = data }
end

--[[
    题库加载状态（排查用）
    @return table {code, data}
]]
function CMD.status()
    if not g_ctx then
        return { code = 0, msg = "题库未加载" }
    end
    return { code = 1, data = g_ctx:status() }
end

--[[
    重新加载题库；传 gameid 只重载该游戏
    @return table {code, data|msg}
]]
function CMD.reload(gameid)
    log.info("[questionBank] 收到题库重载请求 gameid=%s", tostring(gameid))
    if not g_ctx then
        return { code = 0, msg = "题库未加载" }
    end
    local ok, err = g_ctx:reload(gameid)
    if not ok then
        return { code = 0, msg = err }
    end
    return CMD.status()
end

skynet.start(function()
    -- 启动即加载题库；失败只记录错误，接口按约定返回错误码
    loadBank()

    skynet.dispatch("lua", function(session, source, cmd, ...)
        local handler = CMD[cmd]
        if not handler then
            log.error("[questionBank] 未知接口: %s", tostring(cmd))
            skynet.ret(skynet.pack({ code = 0, msg = string.format("接口不存在: %s", tostring(cmd)) }))
            return
        end
        skynet.ret(skynet.pack(handler(...)))
    end)
end)
