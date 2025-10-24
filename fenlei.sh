cat > ~/fenlei.sh << 'EOF'
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
declare -A file_map

echo "（第1轮）正在扫描目标目录并建立索引..."
echo "目标: $TARGET_DIR"

# 遍历 *指定目录* 下所有符合 '[*]*. ' 模式的文件
for file_path in "$TARGET_DIR"/\[*\].*; do
    
    # 关键检查: 只处理常规文件, 跳过文件夹
    [ -f "$file_path" ] || continue
    
    # 从完整路径中提取文件名
    filename=$(basename "$file_path")
    
    # 初始化 $tag
    tag=""

    # =========================================================================
    # 核心提取逻辑 (V8 - 最终修正版)
    # =========================================================================

    # 步骤 1: 绝对严格地只提取 *第一个* [ ... ] 之间的内容
    # *** 修正(V8): 移除此处的引号, 否则 Bash 会把它当作
    #     一个"字符串"而不是"正则表达式", 导致0匹配 ***
    if [[ "$filename" =~ ^\[([^]]+)\] ]]; then
        
        # inner_content 现在是 "aaa(bbb)" 或者 "aaa"
        inner_content="${BASH_REMATCH[1]}"
        
        # 步骤 2: 检查这个 inner_content 是否包含 (bbb) 格式
        # *** 修正(V7): 保留此处的引号, 
        #     防止 Bash 报错 "unexpected token `)`" ***
        if [[ "$inner_content" =~ "\(([^)]+)\)" ]]; then
            # 规则 1 命中: 提取 (bbb)
            tag="${BASH_REMATCH[1]}"
        else
            # 规则 2 命中: 使用 "aaa"
            tag="$inner_content"
        fi
    fi
    # =========================================================================


    # 如果成功提取到标签 ( "bbb" 或 "aaa" )
    if [ -n "$tag" ]; then
        # 将此文件的完整路径追加到该标签的“列表”中
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

# 遍历所有被索引的标签
for tag in "${!file_map[@]}"; do
    
    # 读取该标签对应的所有文件路径
    file_list_str=${file_map["$tag"]}
    
    # 将这个字符串读入一个真正的 bash 数组 `files` 中
    IFS=$'\n' read -r -d '' -a files < <(printf '%s\0' "$file_list_str")
    
    # 获取文件数量
    count=${#files[@]}
    
    # 检查数量是否大于等于2
    if [ "$count" -ge 2 ]; then
        
        # 目标文件夹路径
        DEST_FOLDER="$TARGET_DIR/$tag"
        
        # 使用 mkdir -p 确保目标文件夹存在
        mkdir -p "$DEST_FOLDER"
        
        # 提示语
        echo "处理文件夹: $DEST_FOLDER (共 $count 个文件)"
        
        # 遍历这个数组并移动所有文件
        for file_to_move in "${files[@]}"; do
            filename_to_move=$(basename "$file_to_move")
            echo "  -> 移动 $filename_to_move 到 $DEST_FOLDER/"
            
            # 移动文件, 并检查错误
            mv -- "$file_to_move" "$DEST_FOLDER/"
            if [ $? -ne 0 ]; then
                echo "  !!!! 错误: 移动 $filename_to_move 失败 (可能是I/O错误或Rclone挂载已掉线) !!!!"
            else
                ((moved_count++))
            fi
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
EOF
