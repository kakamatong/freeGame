-- wsAuthserver.lua
-- WebSocket 登录认证底层实现，负责加密握手、token校验和连接管理
local skynet = require "skynet"
local websocket = require "http.websocket"
local socket = require "skynet.socket"
local crypt = require "skynet.crypt"
require "skynet.manager"
local log = require "log"
-- WebSocket认证流程，完成加密握手和token解密
local function ws_login(fd)
    -- 生成挑战字符串，防止重放攻击
    local challenge = crypt.randomkey()
    local challenge_b64 = crypt.base64encode(challenge)
    log.info("login challenge_b64 %s", challenge_b64)
    websocket.write(fd, challenge_b64, "binary")

    -- 读取客户端密钥
    local client_key = websocket.read(fd)
    log.info("login client_key_b64 %s", client_key)
    client_key = crypt.base64decode(client_key)
    if #client_key ~= 8 then
        log.info("Invalid client key length")
        error("Invalid client key length")
    end
    -- 生成服务端密钥
    local server_key = crypt.randomkey()
    local server_key_dh = crypt.dhexchange(server_key)
    local server_key_b64 = crypt.base64encode(server_key_dh)
    log.info("login server_key_b64 %s", server_key_b64)
    websocket.write(fd, server_key_b64, "binary")

    -- 计算共享密钥
    local secret = crypt.dhsecret(client_key, server_key)
    -- 验证HMAC，确保通信安全
    local response = websocket.read(fd)
    local hmac = crypt.hmac64(challenge, secret)
    local client_hmac = crypt.base64decode(response)
    if hmac ~= client_hmac then
        error("HMAC validation failed")
    end
    log.info("login handshake success secret %s", crypt.hexencode(secret))
    -- 解密Token，获取用户信息
    local etoken = websocket.read(fd)
    log.info("login etoken %s", etoken)
    local token = crypt.desdecode(secret, crypt.base64decode(etoken))
    log.info("login token %s", token)
    return token, secret
end

-- WebSocket连接处理器，负责整个登录流程
local function handle_ws_connection(fd, addr, ip, conf)
    local ok, token, secret = pcall(ws_login, fd)
    if not ok then
        websocket.write(fd, "401 Unauthorized", "binary")
        websocket.close(fd)
        return
    end
    -- 调用认证逻辑
    local ok, srv, uid, loginType = pcall(conf.login_handler, token, ip)
    if not ok then
        websocket.write(fd, "403 Forbidden", "binary")
        websocket.close(fd)
        return
    end
    -- 调用登录逻辑
    local ok, subid = pcall(conf.login_after_handler, srv, uid, secret, loginType)
    if not ok then
        websocket.write(fd, "406 Not Acceptable", "binary")
        websocket.close(fd)
        return
    end
    log.info("login subid %s", subid)
    -- 返回登录成功信息
    websocket.write(fd, "200 "..crypt.base64encode(subid) .. " " .. crypt.base64encode(uid), "binary")
    websocket.close(fd)
end

-- 启动WebSocket登录服务，监听端口并处理连接
local function login(conf)
    assert(conf.login_handler)
	assert(conf.command_handler)
    assert(conf.host)
    assert(conf.port)
    assert(conf.name)

    skynet.start(function()
        -- 添加WebSocket监听
        local id = socket.listen(conf.host, conf.port)
        log.info(string.format("WebSocket login server listening on %s:%d", conf.host, conf.port))
        
        socket.start(id, function(fd, addr)
            log.info("login websocket add %s", addr)
            local ok, err = websocket.accept(fd, {
                handshake = function(fd, header, url)
                    log.info("login handshake %s",url)
                    local ip = websocket.real_ip(fd)
                    pcall(handle_ws_connection, fd, addr, ip, conf)
                    return true  -- 接受所有连接
                end,
                connect = function(fd)
                    log.info("login connect %d",fd)
                end,
                closed = function(fd)
                    websocket.close(fd)
                end
            })
            
            if not ok then
                log.error("WebSocket connection failed: "..tostring(err))
            end
        end)

        -- 处理命令分发
        skynet.dispatch("lua", function(_,source,command, ...)
            skynet.ret(skynet.pack(conf.command_handler(command, ...)))
        end)

        local name = conf.name or '.wslogin'
        skynet.register(name)
    end) 
end

return login