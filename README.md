# freeGame
基于skynet的游戏服务端，cluster模式，单节点在分支main_oneNode

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

### 集群配置如下
``` json
{
    "list": {
        "match": [
            {
                "addr": "127.0.0.1:13001",
                "name": "match1",
                "cnt": 1
            }
        ],
        "robot": [
            {
                "addr": "127.0.0.1:13007",
                "name": "robot1",
                "cnt": 1
            }
        ],
        "game": [
            {
                "addr": "127.0.0.1:13002",
                "name": "game1",
                "cnt": 1,
                "clientAddr": "ws://192.168.1.140:9003"
            },
            {
                "addr": "127.0.0.1:13015",
                "name": "game2",
                "cnt": 1,
                "clientAddr": "ws://192.168.1.140:9006",
				"hide": true
            }
        ],
        "login": [
            {
                "addr": "127.0.0.1:13004",
                "name": "login1",
                "cnt": 1,
                "clientAddr": "ws://192.168.1.140:8002"
            }
        ],
        "user": [
            {
                "addr": "127.0.0.1:13006",
                "name": "user1",
                "cnt": 8
            }
        ],
        "gate": [
            {
                "addr": "127.0.0.1:13005",
                "name": "gate1",
                "cnt": 1,
                "clientAddr": "ws://192.168.1.140:9002"
            },
            {
                "addr": "127.0.0.1:13012",
                "name": "gate2",
                "cnt": 1,
                "clientAddr": "ws://192.168.1.140:9005"
            }
        ],
        "activity": [
            {
                "addr": "127.0.0.1:13009",
                "name": "activity1",
                "cnt": 1
            }
        ],
        "auth": [
            {
                "addr": "127.0.0.1:13010",
                "name": "auth1",
                "cnt": 8
            }
        ],
		"web": [
			{
                "addr": "127.0.0.1:13020",
                "name": "web1",
                "cnt": 1
            }
		]
    },
    "ver": 11
}
```

集群控制代码在clusterManager目录下，每2分钟从redis拉去配置，对比ver，如果不一致则刷新，可动态增加节点和节点服务，也可隐藏节点，等节点没有链接以后，下架节点