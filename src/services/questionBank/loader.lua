--[[
    loader.lua
    题库服务框架：按 gameid 把请求分发到各游戏模块，负责加载、缓存与错误记录
    设计原则：
    - 不同游戏的题库 json 格式、校验方式、对外数据结构都不同，因此**一个游戏一份代码**；
    - 框架只认 gameid 做分发与缓存，**不解释**游戏模块的 state 与对外返回 table；
    - 本模块不依赖 skynet，可离线单测。

    游戏模块契约（games/<gameid>.lua）：
      M.gameid                           必须：声明负责的游戏id
      M.load(dataDir)         -> state | nil, err     必须：加载本游戏题库
      M.pick(state, difficultyId, opts) -> data | nil, err  必须：取一道题（data 结构由游戏决定）
      M.info(state)           -> data | nil, err     可选：题库信息
]]

local loader = {}

-- 题库默认根目录（相对服务进程工作目录，即仓库根）
loader.DEFAULT_DATA_ROOT = "./src/services/questionBank/data"

--[[
    创建题库上下文
    @param dataRoot string|nil 题库根目录
    @param registry table|nil 预加载游戏清单（games/registry.lua）
    @return table 上下文（含 loadGame/preload/get/reload/status 方法）
]]
function loader.new(dataRoot, registry)
    local ctx = {
        dataRoot = dataRoot or loader.DEFAULT_DATA_ROOT,
        registry = registry or {},
        games = {},  -- [gameid] = {gameid, module, state, dataDir}
        errors = {}, -- [gameid] = 错误信息
    }

    --[[
        解析 gameid 对应的模块名（只接受纯数字，避免 require 越界）
        @return string|nil 模块名  @return number|nil gameid 或错误信息
    ]]
    local function moduleOf(gameid)
        local text = tostring(gameid)
        if not string.match(text, "^%d+$") then
            return nil, string.format("非法 gameid: %s", text)
        end
        return string.format("questionBank.games.%s", text), tonumber(text)
    end

    --[[
        加载（或重新加载）一个游戏题库
        @return table|nil 游戏条目  @return string|nil 错误信息
    ]]
    function ctx:loadGame(gameid)
        local moduleName, gid = moduleOf(gameid)
        if not moduleName then
            return nil, gid
        end
        local ok, module = pcall(require, moduleName)
        if not ok or type(module) ~= "table" then
            return nil, string.format("未实现该游戏的题库模块: %s", tostring(gameid))
        end
        if type(module.load) ~= "function" then
            return nil, string.format("游戏 %s 题库模块缺少 load 方法", tostring(gameid))
        end

        local dataDir = string.format("%s/%s", self.dataRoot, tostring(gid))
        local state, err = module.load(dataDir)
        if not state then
            return nil, err or "题库加载失败"
        end

        self.games[gid] = { gameid = gid, module = module, state = state, dataDir = dataDir }
        self.errors[gid] = nil
        return self.games[gid], nil
    end

    -- 按 registry 清单预加载
    function ctx:preload()
        for _, gameid in ipairs(self.registry) do
            local game, err = self:loadGame(gameid)
            if not game then
                self.errors[tonumber(gameid) or gameid] = err
            end
        end
    end

    --[[
        取游戏条目；未加载过则按需加载（用于已实现但未登记 registry 的游戏）
    ]]
    function ctx:get(gameid)
        local gid = tonumber(gameid)
        if not gid then
            return nil, "参数错误: gameid 必须为数字"
        end
        local game = self.games[gid]
        if game then
            return game, nil
        end
        if self.errors[gid] then
            return nil, self.errors[gid]
        end
        local loaded, err = self:loadGame(gid)
        if not loaded then
            self.errors[gid] = err
            return nil, err
        end
        return loaded, nil
    end

    --[[
        重新加载：指定 gameid 则只重载该游戏，否则全量重载
    ]]
    function ctx:reload(gameid)
        if gameid then
            local gid = tonumber(gameid)
            if not gid then
                return nil, "参数错误: gameid 必须为数字"
            end
            self.errors[gid] = nil
            local game, err = self:loadGame(gid)
            if not game then
                self.errors[gid] = err
                return nil, err
            end
            return game, nil
        end
        self.games = {}
        self.errors = {}
        self:preload()
        return true, nil
    end

    --[[
        加载状态（只含目录与计数类信息，不返回题目内容）
    ]]
    function ctx:status()
        local games = {}
        for gid, game in pairs(self.games) do
            local item = { dataDir = game.dataDir }
            if type(game.module.info) == "function" then
                local ok, info = pcall(game.module.info, game.state)
                if ok and type(info) == "table" then
                    item.info = info
                end
            end
            games[tostring(gid)] = item
        end
        return { dataRoot = self.dataRoot, games = games, errors = self.errors }
    end

    return ctx
end

return loader
