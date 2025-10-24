#!/bin/bash

# ==========================================================
# 设定目标目录
TARGET_DIR="/xiazai/rclone/移动云盘/漫画/h/mi"
# ==========================================================

# 检查目标目录是否存在
if [ ! -d "$TARGET_DIR" ]; then
    echo "错误: 目标目录不存在!"
    echo "请检查路径: $TARGET_DIR"
    exit 1
fi

# 1. 声明一个关联数组 (哈希表) 来存储每个标签 (key) 及其文件数量 (value)
declare -A counts

echo "（第1轮）正在扫描目标目录并统计标签..."
echo "目标: $TARGET_DIR"

# 遍历 *指定目录* 下所有符合 '[*]*. ' 模式的文件或文件夹
for file_path in "$TARGET_DIR"/\[*\].*; do
    
    # 关键检查 (1): 如果 $file_path 不是一个常规文件 (例如它是一个文件夹),
    #             则跳过它, 不进行统计。
    [ -f "$file_path" ] || continue
    
    # 从完整路径中提取文件名
    filename=$(basename "$file_path")

    # =========================================================================
    # 规则 1: 优先提取 [author(artist)] 中的 'artist'
    #         [^()\]]* -> 匹配任何不是 '(', ')' 或 ']' 的字符 (即 author)
    #         \([^)]*\) -> 捕获 'artist' (捕获组2)
    tag=$(echo "$filename" | sed -n 's/^\[\([^()\]*\)(\([^)]*\))[^]]*\].*/\2/p')
    
    # 规则 2: 如果规则 1 没匹配到 (即 $tag 为空), 则尝试提取 [author] 中的 'author'
    #         [^()\]]* -> 匹配任何不是 '(', ')' 或 ']' 的字符 (即 author) (捕获组1)
    if [ -z "$tag" ]; then
        tag=$(echo "$filename" | sed -n 's/^\[\([^()\]*\)\].*/\1/p')
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

# 再次遍历 *指定目录* 的所有文件或文件夹
for file_path in "$TARGET_DIR"/\[*\].*; do

    # 关键检查 (2): 同样, 如果 $file_path 不是一个常规文件 (是文件夹),
    #             则跳过它, 不进行移动。
    [ -f "$file_path" ] || continue
    
    # 提取文件名
    filename=$(basename "$file_path")

    # =========================================================================
    # 规则 1: 优先提取 [author(artist)] 中的 'artist'
    tag=$(echo "$filename" | sed -n 's/^\[\([^()\]*\)(\([^)]*\))[^]]*\].*/\2/p')
    
    # 规则 2: 如果规则 1 没匹配到 (即 $tag 为空), 则尝试提取 [author] 中的 'author'
    if [ -z "$tag" ]; then
        tag=$(echo "$filename" | sed -n 's/^\[\([^()\]*\)\].*/\1/p')
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
        
        # 创建的目标文件夹路径
        DEST_FOLDER="$TARGET_DIR/$tag"
        
        # 检查目标文件夹是否已创建, 未创建则创建
        if [ ! -d "$DEST_FOLDER" ]; then
            echo "创建文件夹: $DEST_FOLDER (共 $count 个文件)"
            mkdir -p "$DEST_FOLDER"
        fi
        
        # 移动文件
        echo "  -> 移动 $filename 到 $DEST_FOLDER/"
        mv -- "$file_path" "$DEST_FOLDER/"
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
