#!/bin/bash

# 生成400条userData表的插入SQL，保存到tools/insert_userdata.sql
provinces=("Guangdong" "Beijing" "Jiangsu" "Zhejiang" "Shandong" "Sichuan" "Hubei" "Fujian" "Liaoning" "Shaanxi")

province_names=(
"Guangdong:广东省"
"Beijing:北京市"
"Jiangsu:江苏省"
"Zhejiang:浙江省"
"Shandong:山东省"
"Sichuan:四川省"
"Hubei:湖北省"
"Fujian:福建省"
"Liaoning:辽宁省"
"Shaanxi:陕西省"
)

cities_Guangdong=("广州市" "深圳市" "珠海市" "汕头市")
cities_Beijing=("东城区" "西城区" "朝阳区" "海淀区")
cities_Jiangsu=("南京市" "苏州市" "无锡市" "常州市")
cities_Zhejiang=("杭州市" "宁波市" "温州市" "嘉兴市")
cities_Shandong=("济南市" "青岛市" "烟台市" "潍坊市")
cities_Sichuan=("成都市" "绵阳市" "德阳市" "乐山市")
cities_Hubei=("武汉市" "黄石市" "襄阳市" "宜昌市")
cities_Fujian=("福州市" "厦门市" "泉州市" "漳州市")
cities_Liaoning=("沈阳市" "大连市" "鞍山市" "抚顺市")
cities_Shaanxi=("西安市" "咸阳市" "宝鸡市" "渭南市")

random_nickname() {
    nicks=(
        "梦幻银河" "星空旅者" "月光战士" "彩虹猎人" "暴风骑士" "冰霜法师" "火焰舞者" "雷电法王"
        "幻影刺客" "神秘盗贼" "光明圣骑" "暗夜精灵" "烈火剑仙" "寒冰女王" "风暴之眼" "大地守护"
        "天空之城" "海洋之心" "森林精灵" "沙漠之鹰" "雪山飞狐" "草原狼王" "深海巨鲸" "高山雄鹰"
        "春风十里" "夏日清凉" "秋叶满山" "冬雪纷飞" "晨曦初照" "夕阳西下" "午夜星辰" "黎明破晓"
        "飞龙在天" "猛虎下山" "雄狮怒吼" "神鹰展翅" "游龙戏水" "凤凰涅槃" "麒麟送福" "白虎威武"
        "紫气东来" "金光闪闪" "银装素裹" "翠绿满园" "火红热情" "天蓝如洗" "雪白纯洁" "墨黑深邃"
        "剑走偏锋" "刀光剑影" "枪林弹雨" "棍棒无敌" "拳拳到肉" "掌掌生风" "腿功了得" "轻功盖世"
        "诗酒年华" "琴棋书画" "花鸟鱼虫" "山水情怀" "风花雪月" "春花秋月" "夏荷冬梅" "竹林听雨"
        "码农小哥" "设计大神" "产品经理" "运营达人" "测试专家" "架构师" "全栈工程师" "算法专家"
        "电竞高手" "游戏王者" "娱乐达人" "音乐天才" "舞蹈精灵" "书法大师" "绘画高手" "摄影师"
        "美食家" "旅行者" "读书人" "运动健将" "健身达人" "瑜伽大师" "跑步狂人" "游泳健将"
        "咖啡爱好者" "茶道高手" "红酒专家" "啤酒达人" "甜品控" "辣食狂" "清淡派" "重口味"
        "夜猫子" "早起鸟" "午睡王" "熬夜党" "闹钟杀手" "时间管理" "效率专家" "拖延症"
        "乐观派" "悲观者" "现实主义" "理想主义" "完美主义" "随性派" "细节控" "大而化之"
        "北方汉子" "江南才子" "西部牛仔" "东北虎" "四川辣妹" "湖南辣椒" "广东靓仔" "上海小资"
        "温柔如水" "热情如火" "清新如风" "稳重如山" "活泼如兔" "机智如猴" "憨厚如熊" "灵巧如猫"
        "学霸本霸" "学渣也疯狂" "考试必过" "作业终结者" "课堂睡神" "笔记达人" "错题收集" "满分王者"
        "加班狂魔" "摸鱼专家" "会议达人" "PPT高手" "Excel大神" "Word专家" "邮件王者" "报告杀手"
        "网购达人" "省钱专家" "败家子" "理财高手" "投资大神" "股市韭菜" "基金王者" "存款专家"
        "社交牛逼症" "社交恐惧症" "话痨本痨" "沉默是金" "段子手" "冷笑话王" "表情包制造机" "群聊活跃分子"
    )
    echo "${nicks[$RANDOM % ${#nicks[@]}]}"
}

out="tools/insert_userdata.sql"

mkdir -p tools

echo "" > "$out"

for i in $(seq 0 399); do
    userid=$((10050 + i))
    nickname=$(random_nickname)
    headurl=""
    sex=$((RANDOM % 2 + 1))
    pidx=$((RANDOM % ${#provinces[@]}))
    province_key=${provinces[$pidx]}
    
    # 获取省份中文名
    for kv in "${province_names[@]}"; do
        key="${kv%%:*}"
        value="${kv##*:}"
        if [[ "$key" == "$province_key" ]]; then
            province_cn="$value"
            break
        fi
    done
    
    # 获取城市
    eval "citys=(\"\${cities_${province_key}[@]}\")"
    city=${citys[$((RANDOM % ${#citys[@]}))]}
    
    ip="0.0.0.0"
    ext=""
    
    echo "INSERT INTO \`userData\` (\`userid\`, \`nickname\`, \`headurl\`, \`sex\`, \`province\`, \`city\`, \`ip\`, \`ext\`, \`create_time\`, \`update_time\`) VALUES ($userid, '$nickname', '$headurl', $sex, '$province_cn', '$city', '$ip', '$ext', NOW(), NOW());" >> "$out"
done

echo "已生成 tools/insert_userdata.sql，包含400条随机用户数据插入语句，userid从10050开始。"