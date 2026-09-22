--[[
    games/registry.lua
    需要预加载的游戏题库模块清单
    说明：服务启动时按此清单逐个加载；请求其它已实现但未登记的 gameid 时按需加载。
    新增游戏：写 games/<gameid>.lua 后，把 gameid 登记到这里。
]]

return {
    10003, -- 算24点
}
