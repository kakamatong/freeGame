--[[
    games/10003.lua
    算24点(10003)题库适配模块
    说明：每个游戏一份这样的文件，自己决定题库格式、校验规则与对外返回的数据结构。
    服务框架只按 gameid 把请求转给本模块，不解释本模块返回的 table。

    本题库格式（仅本游戏使用）：
      <游戏目录>/meta.json      { gameid, ruleVersion, dealCount, numberRange, difficulties=[{id,name,file,count}] }
      <游戏目录>/<难度id>.json  [ { id, numbers[4], solution, variants?, tags? } ]

    对外 pick 返回（本游戏自定义）：
      { gameid, id, numbers, difficulty, ruleVersion }
      solution / tags / variants 属内部字段，不出对外 table。
]]

local util = require "questionBank.util"

local M = {}

M.gameid = 10003

--[[
    校验单条题目
    @param puzzle table 题目
    @param dealCount number 每局发牌数量
    @return string|nil 错误信息，合法返回 nil
]]
local function checkPuzzle(puzzle, dealCount)
    if type(puzzle) ~= "table" then
        return "题目不是对象"
    end
    if type(puzzle.id) ~= "string" or puzzle.id == "" then
        return "题目缺少 id"
    end
    if type(puzzle.numbers) ~= "table" then
        return string.format("题目 %s 缺少 numbers", puzzle.id)
    end
    if #puzzle.numbers ~= dealCount then
        return string.format("题目 %s 的 numbers 数量不是 %d", puzzle.id, dealCount)
    end
    for i = 1, #puzzle.numbers do
        if type(puzzle.numbers[i]) ~= "number" then
            return string.format("题目 %s 的 numbers 含非数字", puzzle.id)
        end
    end
    return nil
end

--[[
    加载本游戏题库
    @param dataDir string 本游戏的题库目录（框架传入，形如 <题库根>/10003）
    @return table|nil 游戏题库状态（对本服务框架不透明）
    @return string|nil 错误信息
]]
function M.load(dataDir)
    local meta, err = util.readJson(dataDir .. "/meta.json")
    if not meta then
        return nil, err
    end
    if tonumber(meta.gameid) ~= M.gameid then
        return nil, string.format("目录 %s 与 meta.gameid(%s) 不一致", dataDir, tostring(meta.gameid))
    end
    if type(meta.difficulties) ~= "table" or #meta.difficulties == 0 then
        return nil, "meta.json 缺少 difficulties"
    end

    local dealCount = tonumber(meta.dealCount) or 4
    local state = {
        gameid = M.gameid,
        meta = meta,
        ruleVersion = tonumber(meta.ruleVersion) or 0,
        dealCount = dealCount,
        diffs = {},
        idIndex = {},
        total = 0,
    }

    for _, diffMeta in ipairs(meta.difficulties) do
        local diffId = tonumber(diffMeta.id)
        if not diffId then
            return nil, string.format("存在非法难度id: %s", tostring(diffMeta.id))
        end
        if state.diffs[diffId] then
            return nil, string.format("难度id重复: %d", diffId)
        end
        if type(diffMeta.file) ~= "string" or diffMeta.file == "" then
            return nil, string.format("难度 %d 缺少 file", diffId)
        end

        local list, listErr = util.readJson(string.format("%s/%s", dataDir, diffMeta.file))
        if not list then
            return nil, listErr
        end
        for i = 1, #list do
            local puzzleErr = checkPuzzle(list[i], dealCount)
            if puzzleErr then
                return nil, string.format("难度 %d: %s", diffId, puzzleErr)
            end
            if state.idIndex[list[i].id] then
                return nil, string.format("题目id重复: %s", list[i].id)
            end
            state.idIndex[list[i].id] = true
        end
        if diffMeta.count and tonumber(diffMeta.count) ~= #list then
            return nil, string.format("难度 %d 数量不一致: meta=%s 实际=%d",
                diffId, tostring(diffMeta.count), #list)
        end

        state.diffs[diffId] = {
            id = diffId,
            name = diffMeta.name or tostring(diffId),
            list = list,
            count = #list,
            cursor = 0,
        }
        state.total = state.total + #list
    end

    return state
end

--[[
    取某难度的题目列表；不足处返回中文错误
]]
local function getDiff(state, difficultyId)
    if type(state) ~= "table" then
        return nil, "题库未加载"
    end
    local diffId = tonumber(difficultyId)
    if not diffId then
        return nil, "参数错误: 难度id必须为数字"
    end
    local diff = state.diffs[diffId]
    if not diff then
        return nil, string.format("未配置难度: %s", tostring(difficultyId))
    end
    return diff
end

--[[
    按难度取一道题，返回本游戏自定义的对外 table
    @param state table 本游戏题库状态
    @param difficultyId number 难度id
    @param opts table|nil {mode="random"|"seq", excludeIds={...}}
    @return table|nil 对外题目数据
    @return string|nil 错误信息
]]
function M.pick(state, difficultyId, opts)
    local diff, err = getDiff(state, difficultyId)
    if not diff then
        return nil, err
    end
    if diff.count == 0 then
        return nil, string.format("难度 %d 题库为空", diff.id)
    end

    opts = opts or {}
    local exclude = util.buildExclude(opts.excludeIds)
    local list = diff.list
    local puzzle

    if opts.mode == "seq" then
        -- 轮询：按内部游标顺序取，跳过被排除的题目
        for _ = 1, diff.count do
            diff.cursor = diff.cursor % diff.count + 1
            if not (exclude and exclude[list[diff.cursor].id]) then
                puzzle = list[diff.cursor]
                break
            end
        end
    else
        -- 随机：先随机重试，仍失败则顺序兜底，保证排除逻辑正确
        for _ = 1, 30 do
            local candidate = list[math.random(1, diff.count)]
            if not (exclude and exclude[candidate.id]) then
                puzzle = candidate
                break
            end
        end
        if not puzzle then
            for i = 1, diff.count do
                if not (exclude and exclude[list[i].id]) then
                    puzzle = list[i]
                    break
                end
            end
        end
    end

    if not puzzle then
        return nil, string.format("难度 %d 题目已全部被排除", diff.id)
    end

    -- 组织对外数据：只给本局数字与标识，不含答案
    local numbers = {}
    for i = 1, #puzzle.numbers do
        numbers[i] = puzzle.numbers[i]
    end
    return {
        gameid = state.gameid,
        id = puzzle.id,
        numbers = numbers,
        difficulty = diff.id,
        ruleVersion = state.ruleVersion,
    }, nil
end

--[[
    本游戏题库信息（对外 table，由本模块决定结构）
]]
function M.info(state)
    if type(state) ~= "table" then
        return nil, "题库未加载"
    end
    local difficulties = {}
    for _, diff in pairs(state.diffs) do
        table.insert(difficulties, { id = diff.id, name = diff.name, count = diff.count })
    end
    table.sort(difficulties, function(a, b) return a.id < b.id end)
    return {
        gameid = state.gameid,
        ruleVersion = state.ruleVersion,
        total = state.total,
        difficulties = difficulties,
    }, nil
end

return M
