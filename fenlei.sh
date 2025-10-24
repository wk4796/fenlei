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

# 1. 声明一个关联数组 (哈希表)
#    键 (Key)   : 提取到的标签 (e.g., "emily" 或 "artist_bbb")
#    值 (Value) : 一个用换行符(\n)分隔的、包含所有匹配文件路径的字符串
declare -A file_map

echo "（第1轮）正在扫描目标目录并建立索引..."
echo "目标: $TARGET_DIR"

# 遍历 *指定目录* 下所有符合 '[*]*. ' 模式的文件
for file_path in "$TARGET_DIR"/\[*\].*; do
    
    # 关键检查 (1): 只处理常规文件, 跳过文件夹
    [ -f "$file_path" ] || continue
    
    # 从完整路径中提取文件名
    filename=$(basename "$file_path")

    # =========================================================================
    # 规则 1: 优先提取 [author(artist)] 中的 'artist'
    # 匹配 [aaa(bbb)] -> 提取 bbb
    # [^()\]]* : 匹配任何不是 '(', ')' 或 ']' 的字符 (即 aaa)
    # \([^)]*\): 捕获 bbb (捕获组2)
    tag=$(echo "$filename" | sed -n 's/^\[\([^()\]*\)(\([^)]*\))[^]]*\].*/\2/p')
    
    # 规则 2: 如果规则 1 没匹配到 (即 $tag 为空), 则尝试提取 [author] 中的 'author'
    # 匹配 [aaa] -> 提取 aaa
    # [^()\]]* : 匹配任何不是 '(', ')' 或 ']' 的字符 (即 aaa) (捕获组1)
    if [ -z "$tag" ]; then
        tag=$(echo "$filename" | sed -n 's/^\[\([^()\]*\)\].*/\1/p')
    fi
    # =========================================================================

    # 如果成功提取到标签
    if [ -n "$tag" ]; then
        # 将此文件的完整路径追加到该标签的“列表”中
        # 我们用 \n 换行符作为分隔符
        existing_files=${file_map["$tag"]}
        if [ -z "$existing_files" ]; then
            file_map["$tag"]="$file_path"
        else
            file_map["$tag"]="$existing_files"$'\n'"$file_path"
        fi
    fi
done

echo "索引完成。"
echo "（第2轮）开始处理索引并移动文件..."

moved_count=0
# 声明一个数组来跟踪未处理的标签
declare -a unprocessed_tags

# 遍历所有被索引的标签 (即 file_map 的所有 "key")
for tag in "${!file_map[@]}"; do
    
    # 读取该标签对应的所有文件路径 (这是一个用 \n 分隔的字符串)
    file_list_str=${file_map["$tag"]}
    
    # 将这个字符串读入一个真正的 bash 数组 `files` 中
    # 这样可以正确处理带空格的文件名
    IFS=$'\n' read -r -d '' -a files < <(printf '%s\0' "$file_list_str")
    
    # 获取文件数量
    count=${#files[@]}
    
    # 检查数量是否大于等于2
    if [ "$count" -ge 2 ]; then
        
        # 创建的目标文件夹路径
        DEST_FOLDER="$TARGET_DIR/$tag"
        echo "创建文件夹: $DEST_FOLDER (共 $count 个文件)"
        mkdir -p "$DEST_FOLDER"
        
        # 遍历这个数组并移动所有文件
        for file_to_move in "${files[@]}"; do
            filename_to_move=$(basename "$file_to_move")
            echo "  -> 移动 $filename_to_move 到 $DEST_FOLDER/"
            mv -- "$file_to_move" "$DEST_FOLDER/"
            ((moved_count++))
        done
        
    else
        # 数量不足, 记录下来
        unprocessed_tags+=("$tag (数量: $count)")
    fi
done

echo "------------------------------"
echo "操作完成。共移动 $moved_count 个文件。"

# 打印出那些没有被移动的标签
echo "---"
echo "以下标签因文件数量不足2个而未被处理:"
if [ ${#unprocessed_tags[@]} -eq 0 ]; then
    echo "  (无)"
else
    # 循环打印所有数量为1的标签
    for item in "${unprocessed_tags[@]}"; do
        echo "  - $item"
    done
fi
