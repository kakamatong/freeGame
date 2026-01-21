# 广告奖励活动功能测试文档

## 功能概述
实现了`ad.lua`活动模块，用于每天看视频广告领取奖励。

## 已实现的功能

### 1. 核心文件
- `/root/freeGame/src/services/activity/ad.lua` - 广告奖励活动模块

### 2. 接口功能

#### 2.1 获取活动配置接口 - `getAdInfo`
```lua
-- 调用方式
activity.ad.getAdInfo(userid, args)

-- 返回数据
{
    maxDailyRewardCount: 5,        -- 每日最大领取次数（可配置）
    currentRewardCount: 2,         -- 当前已领取次数
    rewards: [                     -- 奖励配置
        {
            richTypes: [1],        -- 道具类型
            richNums: [10]         -- 道具数量
        }
    ],
    canReward: true                -- 是否还能领取奖励
}
```

#### 2.2 领奖接口 - `getAdReward`
```lua
-- 调用方式
activity.ad.getAdReward(userid, args)

-- 返回数据
{
    noticeid: 123,                 -- 奖励通知ID
    reward: {                      -- 获得的奖励
        richTypes: [1],
        richNums: [10]
    },
    currentRewardCount: 3,         -- 更新后的已领取次数
    maxDailyRewardCount: 5
}
```

### 3. Redis数据管理

#### 3.1 数据结构
```json
{
    "lastRewardTime": 1703847600,    -- 最后领取时间戳
    "dailyRewardCount": 2,           -- 当日已领取次数
    "rewardDate": 20240130           -- 最后领取日期（YYYYMMDD）
}
```

#### 3.2 Redis键名
- 用户数据：`adReward:{userid}`
- 锁键：`adLock:{userid}`

#### 3.3 过期策略
- 用户数据：24小时过期
- 锁：2秒自动过期

### 4. 配置管理

#### 4.1 默认配置
```lua
local adConfig = {
    maxDailyRewardCount = 5,  -- 每天最大领取次数
    rewards = {
        {
            richTypes = {CONFIG.RICH_TYPE.SILVER_COIN},
            richNums = {10}
        }
    }
}
```

#### 4.2 配置说明
- 配置直接写在代码中，需要修改时更新ad.lua文件
- 支持自定义每日领取次数和奖励配置

### 5. 安全机制

#### 5.1 并发控制
- 使用Redis锁防止并发领取
- 双重检查机制确保数据一致性

#### 5.2 每日重置
- 自动检测跨天并重置领取次数
- 基于日期而不是时间戳进行重置判断

#### 5.3 数据验证
- 配置格式验证
- 奖励发放失败回滚机制

### 6. 客户端调用方式

#### 6.1 使用现有的活动调用协议
```protobuf
callActivityFunc 8 {
    request {
        moduleName 0 : string  // "ad"
        funcName 1 : string    // "getAdInfo" 或 "getAdReward"
        args 2 : string       // JSON格式的参数
    }
}
```

#### 6.2 示例调用
```lua
-- 获取活动信息
callActivityFunc {
    moduleName: "ad",
    funcName: "getAdInfo",
    args: "{}"
}

-- 领取奖励
callActivityFunc {
    moduleName: "ad", 
    funcName: "getAdReward",
    args: "{}"
}
```

### 7. 错误处理
- 今日奖励已领完：`"今日奖励已领完"`
- 操作频繁：`"操作频繁，请稍后再试"`
- 发奖失败：`"发奖失败"`
- 配置错误：`"配置参数错误"`

### 8. 特性总结
✅ 支持配置化的每日领取次数
✅ 支持配置化的奖励类型和数量  
✅ Redis状态管理，24小时自动过期
✅ 跨天自动重置领取次数
✅ 并发安全控制
✅ 奖励发放和通知机制
✅ 完整的错误处理

## 使用说明
1. 客户端先调用`getAdInfo`获取当前活动状态
2. 检查`canReward`字段判断是否可以领取
3. 如果可以领取，调用`getAdReward`接口
4. 系统会自动发放奖励并更新状态