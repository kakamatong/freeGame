# freeGame
基于skynet的游戏服务端

### skynet
编译需要修改skynet里面的makefile内容，修改如下，增加了cjon库，可以参考根目录/build/下面的makefile

```makefile
    LUA_CLIB = skynet \
    client cjson\
    bson md5 sproto lpeg $(TLS_MODULE)
```

```makefile
    $(LUA_CLIB_PATH)/cjson.so : 3rd/lua-cjson/lua_cjson.c 3rd/lua-cjson/fpconv.c 3rd/lua-cjson/strbuf.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) -I3rd/lua-cjson $^ -o $@ 
```

直接git拉取cjson库到skynet/3rd目录下

cjson使用云风版本：https://github.com/cloudwu/lua-cjson

log 模块使用 https://github.com/Veinin/skynet-logger

### 协议
采用自带的sproto

### 通信
采用websocket
