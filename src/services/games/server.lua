local skynet = require "skynet"
local log = require "log"
local CMD = {}

local path = "games."
local config = require "games.config"
local sharedata = require "skynet.sharedata"

local parser = require "sprotoparser"

local function loadfile(filename)
    local f = assert(io.open(filename), "Can't open sproto file")
    local data = f:read "a"
    f:close()
    return parser.parse(data)
end

local function loadSproto()
    for _, gameid in ipairs(config.gameids) do
        local filename = "proto/" .. string.format("game%d", gameid) .. "/c2s.sproto"
        local bin = loadfile(filename)
        local data = {
            str = bin,
        }
        sharedata.new("game" .. gameid .. "_c2s", data)

        filename = "proto/" .. string.format("game%d", gameid) .. "/s2c.sproto"
        bin = loadfile(filename)
        data = {
            str = bin,
        }
        sharedata.new("game" .. gameid .. "_s2c", data)
    end
end

local function start()
    local ok,err = pcall(loadSproto)
    if not ok then
        log.error("loadSproto error %s", err)
    end
end

local function callFunc(moduleName, funcName, args)
    local svrModule = nil
    local ok, err = pcall(function()
        svrModule = require(path .. moduleName)
    end)
    if not ok or not svrModule then
        return 
    end
    local func = svrModule[funcName]
    if not func then
        return 
    end

    return func(args)
end

function CMD.svrCall(moduleName, funcName, args)
    log.info("game svrCall %s %s", moduleName, funcName)
    return callFunc(moduleName, funcName, args)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)

    
    start()
end)