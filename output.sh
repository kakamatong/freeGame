# 判断output目录是否存在，存在则删除
if [ -d "output" ]; then
    rm -rf output/*
fi

# 判断output.zip是否存在，存在则删除
if [ -f "output.zip" ]; then
    rm -f output.zip
fi

# 创建output目录
mkdir -p output
mkdir -p output/skynet

# 将src目录拷贝到output目录下
cp -r src output/
cp -r config output/
cp -r proto output/
# skynet目录
cp skynet/skynet output/skynet
cp -r skynet/cservice output/skynet
cp -r skynet/lualib output/skynet
cp -r skynet/luaclib output/skynet
cp -r skynet/service output/skynet

# 将run.sh和stop.sh拷贝到output目录下
cp run.sh output/
cp stop.sh output/

# 将output目录压缩为output.zip
zip -r output.zip output

# 删除output目录
rm -rf output
