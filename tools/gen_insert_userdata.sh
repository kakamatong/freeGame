#!/bin/bash
# 生成50条userData表的插入SQL，保存到tools/insert_userdata.sql

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
        "快乐小熊" "电竞少年" "夜空之星" "风一样的男子" "可爱多" "吃瓜群众" "王者小猪" "学霸少女"
        "元气满满" "皮卡丘" "追风少年" "星辰大海" "打工人" "快乐水手" "游戏达人" "无敌小可爱"
        "阳光宅男" "元气少女" "电竞大神" "小明同学" "小马哥" "小仙女" "大力水手" "小机灵"
        "小糊涂" "小太阳" "小宇宙" "小霸王" "小可爱" "小天才" "小迷糊" "小幸运" "小叮当"
        "小马达" "小飞侠" "小超人" "小王子" "小公主" "小精灵" "小魔王" "小怪兽" "小呆萌"
        "小暖男" "小甜心" "小憨憨" "小憨豆" "小憨包" "小憨憨" "小憨憨" "小憨憨"
    )
    echo "${nicks[$RANDOM % ${#nicks[@]}]}"
}

out="insert_userdata.sql"
mkdir -p tools
echo "" > "$out"

for i in $(seq 0 49); do
    userid=$((10000 + i))
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

echo "已生成 tools/insert_userdata.sql，包含50条随机用户数据插入语句。"