#!/bin/bash

# 1. 声明一个关联数组 (哈希表) 来存储每个标签 (key) 及其文件数量 (value)
declare -A counts

echo "（第1轮）正在扫描当前目录并统计标签..."

# 遍历 *当前目录* 下所有符合 '[*]*. ' 模式的文件或文件夹
for file in \[*\].*; do
    
    # 关键检查 (1): 必须是文件
    [ -f "$file" ] || continue
    
    # =========================================================================
    # 新逻辑: 优先提取 (xxx)
    # 1. 尝试提取 (xxx) 
    #    sed 1: 's/^\[.*(\([^)]*\)).*\].*/\1/p' 捕获括号内的内容
    #    sed 2: 's/^[[:space:]]*//;s/[[:space:]]*$//' 清理捕获内容前后的空格
    tag_paren=$(echo "$file" | sed -n 's/^\[.*(\([^)]*\)).*\].*/\1/p' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 2. 检查是否成功提取到 (xxx)
    if [ -n "$tag_paren" ]; then
        # 如果成功, 使用 (xxx) 作为标签
        tag="$tag_paren"
    else
        # 3. 如果未提取到 (xxx) (例如文件名是 [aa] 这种格式)
        #    回退到提取 [aa] 的逻辑
        tag=$(echo "$file" | sed -n 's/^\[[[:space:]]*\([^](]*\)[^]]*\].*/\1/p')
    fi
    # =========================================================================
    
    # 如果成功提取到标签 (标签非空)
    if [ -n "$tag" ]; then
        # 增加该标签的计数
        ((counts["$tag"]++))
    fi
done

echo "统计完成。"
echo "（第2轮）开始处理和移动文件..."

moved_count=0

# 再次遍历 *当前目录* 的所有文件或文件夹
for file in \[*\].*; do

    # 关键检查 (2): 必须是文件
    [ -f "$file" ] || continue
    
    # =========================================================================
    # 关键: 必须使用与第1轮 *完全相同* 的提取逻辑
    # 1. 尝试提取 (xxx) 
    tag_paren=$(echo "$file" | sed -n 's/^\[.*(\([^)]*\)).*\].*/\1/p' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 2. 检查是否成功提取到 (xxx)
    if [ -n "$tag_paren" ]; then
        tag="$tag_paren"
    else
        # 3. 回退到提取 [aa] 的逻辑
        tag=$(echo "$file" | sed -n 's/^\[[[:space:]]*\([^](]*\)[^]]*\].*/\1/p')
    fi
    # =========================================================================
    
    if [ -z "$tag" ]; then
        # 无法解析, 跳过
        continue
    fi
    
    # 获取这个标签的最终统计数量
    count=${counts["$tag"]}
    
    # 检查数量是否大于等于2
    if [[ -n "$count" && "$count" -ge 2 ]]; then
        
        # 目标文件夹就是标签名, 在当前目录创建
        if [ ! -d "$tag" ]; then
            echo "创建文件夹: $tag (共 $count 个文件)"
            mkdir -p "$tag"
        fi
        
        # 移动文件
        echo "  -> 移动 $file 到 $tag/"
        mv -- "$file" "$tag/"
        ((moved_count++))
    fi
done

echo "------------------------------"
echo "操作完成。共移动 $moved_count 个文件。"

# 打印出那些没有被移动的标签 (数量为1的)
echo "---"
echo "以下标签因文件数量不足2个而未被处理:"
found_unprocessed=0
for tag in "${!counts[@]}"; do
    if [ "${counts["$tag"]}" -lt 2 ]; then
        echo "  - $tag (数量: ${counts["$tag"]})"
        found_unprocessed=1
    fi
done

if [ "$found_unprocessed" -eq 0 ]; then
    echo "  (无)"
fi
