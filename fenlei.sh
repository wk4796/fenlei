#!/bin/bash

# 1. 声明一个关联数组 (哈希表) 来存储每个标签 (key) 及其文件数量 (value)
declare -A counts

echo "（第1轮）正在扫描文件并统计标签..."

# 遍历当前目录下所有符合 '[*]*. ' 模式的文件或文件夹
for file in \[*\].*; do
    
    # ==========================================================
    # 关键检查 (1): 如果 $file 不是一个常规文件 (例如它是一个文件夹),
    #             则跳过它, 不进行统计。
    [ -f "$file" ] || continue
    # ==========================================================
    
    # 提取方括号内的内容, 并处理 (xxx) 的情况
    tag=$(echo "$file" | sed -n 's/^\[\s*\([^](]*\)\s*\(?.*\].*/\1/p')
    
    # 如果成功提取到标签 (标签非空)
    if [ -n "$tag" ]; then
        # 增加该标签的计数
        ((counts["$tag"]++))
    fi
done

echo "统计完成。"
echo "（第2轮）开始处理和移动文件..."

moved_count=0

# 再次遍历所有文件或文件夹
for file in \[*\].*; do

    # ==========================================================
    # 关键检查 (2): 同样, 如果 $file 不是一个常规文件 (是文件夹),
    #             则跳过它, 不进行移动。
    [ -f "$file" ] || continue
    # ==========================================================
    
    # 使用与上面 *完全相同* 的逻辑再次提取标签
    tag=$(echo "$file" | sed -n 's/^\[\s*\([^](]*\)\s*\(?.*\].*/\1/p')
    
    if [ -z "$tag" ]; then
        # 无法解析, 跳过
        continue
    fi
    
    # 获取这个标签的最终统计数量
    count=${counts["$tag"]}
    
    # 检查数量是否大于等于2
    if [[ -n "$count" && "$count" -ge 2 ]]; then
        # 检查目标文件夹是否已创建, 未创建则创建
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
echo "操作完成。共移动 $move_count 个文件。"

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
