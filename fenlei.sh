#!/bin/bash
# [V27 修改] - 综合功能增强版
# 1. (核心增强) 增加自动重命名策略 (遇到重名文件自动追加 _v1, _v2...)。
# 2. (报告增强) 总结报告增加 "自动重命名并归档的文件" 列表。
# 3. (清理功能) 增加 "清理空目录" 功能，在递归处理后自动删除剩下的空文件夹。
# 4. (正则优化) 允许文件名 [ 之前存在空格。
# 5. (底层修复) 扫描阶段使用 -print0/-d '' 彻底解决文件名特殊字符/空格问题。

# ==========================================================
# 脚本全局配置
# ==========================================================
MIN_FILES_FOR_NEW_DIR=2

# ==========================================================
# 核心正则表达式 (V27 优化)
# ==========================================================
# V27: 增加 ^\s* 允许行首有空白字符
RE_STEP_1='^\s*\[([^]]+)\]'  # 匹配 [aaa] 或 [aaa(bbb)]，允许前面有空格
RE_STEP_2='\(([^)]+)\)'      # 匹配 (bbb)

# ==========================================================
# 辅助函数
# ==========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_dryrun() { echo -e "${BLUE}[试运行]${NC} $1"; }

# [V27 新增] 获取唯一文件名 (处理重名)
# 用法: get_unique_filename "目录路径" "文件名"
# 返回: 不冲突的文件名 (原名 或 原名_vN)
get_unique_filename() {
    local dir="$1"
    local filename="$2"
    
    if [ ! -e "$dir/$filename" ]; then
        echo "$filename"
        return
    fi

    local extension="${filename##*.}"
    local filename_no_ext="${filename%.*}"
    local new_name=""
    local counter=1

    # 如果文件没有扩展名 (name == ext)
    if [ "$filename" == "$extension" ]; then
        extension=""
        filename_no_ext="$filename"
    else
        extension=".$extension"
    fi

    while true; do
        new_name="${filename_no_ext}_v${counter}${extension}"
        if [ ! -e "$dir/$new_name" ]; then
            echo "$new_name"
            return
        fi
        ((counter++))
    done
}

show_usage() {
    echo "用法: $0 [选项] [目标目录]"
    echo "选项:"
    echo "  -n, --dry-run    试运行。"
    echo "  -h, --help       显示帮助。"
}

# ==========================================================
# 核心处理函数 (V27 逻辑)
# ==========================================================
process_directory() {
    local TARGET_DIR="$1"
    local IS_DRY_RUN="$2"
    local effective_min_files="$3"
    local IS_RECURSIVE="$4"

    if [ "$IS_DRY_RUN" == "true" ]; then
        log_warn "--- 试运行模式 (DRY RUN) 已激活 ---"
        echo ""
    fi
    
    # 使用 map 存储标签对应的文件列表 (值使用 \n 分隔)
    declare -A file_map
    declare -A tag_sanitize_cache 
    
    log_info "（第1轮）正在扫描目标目录并建立索引..."
    log_info "目标: $TARGET_DIR"
    
    # [V27] 构造 find 命令数组
    local find_args=("$TARGET_DIR")
    if [ "$IS_RECURSIVE" == "false" ]; then
        find_args+=("-maxdepth" "1")
    fi
    
    # [V27] 核心修复: 使用 -print0 和 read -d '' 处理所有怪异文件名
    while IFS= read -r -d '' file_path; do
        
        filename=$(basename "$file_path")
        tag=""

        # 步骤 1: 提取 [ ... ]
        if [[ "$filename" =~ $RE_STEP_1 ]]; then
            inner_content="${BASH_REMATCH[1]}"
            
            # 步骤 2: 提取 ( ... )
            if [[ "$inner_content" =~ $RE_STEP_2 ]]; then
                tag="${BASH_REMATCH[1]}"
            else
                tag="$inner_content"
            fi
        fi

        # 步骤 3: 净化 tag
        if [ -n "$tag" ]; then
            local raw_tag="$tag"
            if [[ -n "${tag_sanitize_cache[$raw_tag]+exists}" ]]; then
                tag="${tag_sanitize_cache[$raw_tag]}"
            else
                local sanitized_tag
                sanitized_tag=$(echo "$raw_tag" | sed -e 's|[/\\:*"<>|]||g' -e 's/\.*$//' -e 's/^\.*//')
                tag_sanitize_cache["$raw_tag"]="$sanitized_tag"
                tag="$sanitized_tag"
            fi
        fi

        # 存入 map (注意: 这里仍使用 \n 作为 map 内部值的分隔符，因为 bash 变量不支持 \0)
        if [ -n "$tag" ]; then
            existing_files=${file_map["$tag"]}
            if [ -z "$existing_files" ]; then
                file_map["$tag"]="$file_path"
            else
                file_map["$tag"]="$existing_files"$'\n'"$file_path"
            fi
        fi
        
    # [V27] find 使用 -print0 输出 null 分隔符
    done < <(find "${find_args[@]}" -type f -name '*\[*\]*' -print0)

    log_info "索引完成。"
    log_info "（第2轮）开始处理索引并移动文件..."

    local moved_count=0
    declare -a unprocessed_tags
    declare -a CREATED_DIRS=()
    declare -a UPDATED_DIRS=()
    declare -a RENAMED_FILES=() # [V27] 记录重命名文件
    declare -a CLEANED_DIRS=()  # [V27] 记录清理的空目录

    for tag in "${!file_map[@]}"; do
        
        local files=()
        mapfile -t files < <(printf '%s' "${file_map["$tag"]}")
        
        local count=${#files[@]}
        local DEST_FOLDER="$TARGET_DIR/$tag"
        local mkdir_needed=false
        local process_group=false

        # 判定逻辑
        if [ -d "$DEST_FOLDER" ]; then
            process_group=true # 文件夹已存在，直接归档
        elif [ "$count" -ge $effective_min_files ]; then
            process_group=true # 达到阈值，需要处理
            mkdir_needed=true
        fi

        if [ "$process_group" == "true" ]; then
            
            # 记录统计信息
            if [ "$mkdir_needed" == "true" ]; then
                echo "处理新文件夹: $DEST_FOLDER (共 $count 个文件)"
                CREATED_DIRS+=("$tag")
            else
                echo "归档到已有文件夹: $DEST_FOLDER (共 $count 个文件)"
                UPDATED_DIRS+=("$tag")
            fi

            # 创建目录
            if [ "$mkdir_needed" == "true" ]; then
                if [ "$IS_DRY_RUN" == "true" ]; then
                    log_dryrun "将创建文件夹: $DEST_FOLDER"
                else
                    mkdir -p "$DEST_FOLDER"
                    if [ $? -ne 0 ]; then
                        log_error "创建目录失败: $DEST_FOLDER"
                        continue
                    fi
                fi
            fi
            
            # 移动文件 (含重命名逻辑)
            for file_to_move in "${files[@]}"; do
                [ -n "$file_to_move" ] || continue
            
                local filename_to_move=$(basename "$file_to_move")
                
                # [V27] 计算目标路径和文件名
                local final_filename="$filename_to_move"
                local dest_file_path="$DEST_FOLDER/$final_filename"
                local renamed_tag=""

                if [ "$IS_DRY_RUN" == "true" ]; then
                    # 试运行模式下简单检查
                    if [ -f "$dest_file_path" ]; then
                         log_dryrun "  -> [重命名] $filename_to_move -> (自动计算_vN) -> $DEST_FOLDER/"
                    else
                         log_dryrun "  -> 移动 $filename_to_move 到 $DEST_FOLDER/"
                    fi
                    ((moved_count++))
                else
                    # --- 实战模式 ---
                    
                    # 1. 检查重名并获取新名字
                    if [ -e "$dest_file_path" ]; then
                        final_filename=$(get_unique_filename "$DEST_FOLDER" "$filename_to_move")
                        dest_file_path="$DEST_FOLDER/$final_filename"
                        renamed_tag=" (重命名为: $final_filename)"
                        
                        # 记录到报告数组
                        RENAMED_FILES+=("$filename_to_move -> $final_filename (在 [$tag] 中)")
                        
                        echo "  -> [重命名] $filename_to_move -> $final_filename"
                    else
                        echo "  -> 移动 $filename_to_move"
                    fi
                    
                    # 2. 执行移动
                    mv -- "$file_to_move" "$dest_file_path"
                    
                    if [ $? -eq 0 ]; then
                        ((moved_count++))
                    else
                        log_error "  移动失败: $file_to_move"
                    fi
                fi
            done
            
        else
            unprocessed_tags+=("$tag (数量: $count)")
        fi
    done

    # [V27] 清理空目录逻辑
    if [ "$IS_RECURSIVE" == "true" ] && [ "$IS_DRY_RUN" == "false" ]; then
        echo ""
        log_info "（第3轮）正在清理扫描留下的空目录..."
        # 查找空目录 (排除目标根目录本身)
        while IFS= read -r -d '' empty_dir; do
            # 双重检查是否为空
            if [ -d "$empty_dir" ] && [ -z "$(ls -A "$empty_dir")" ]; then
                rmdir "$empty_dir"
                if [ $? -eq 0 ]; then
                    CLEANED_DIRS+=("$(basename "$empty_dir")")
                    echo "  -> 删除空目录: $empty_dir"
                fi
            fi
        done < <(find "$TARGET_DIR" -mindepth 1 -type d -empty -print0)
    fi

    echo "------------------------------"
    log_info "操作完成。共移动 $moved_count 个文件。"

    # [V27] 最终报告
    echo ""
    echo -e "${BLUE}--- 总结报告 ---${NC}"
    
    if [ ${#CREATED_DIRS[@]} -gt 0 ]; then
        echo -e "${GREEN}[+] 新创建的文件夹 (${#CREATED_DIRS[@]} 个):${NC}"
        printf "  - %s\n" "${CREATED_DIRS[@]}"
    fi
    
    if [ ${#UPDATED_DIRS[@]} -gt 0 ]; then
        echo -e "${GREEN}[~] 归档到已有文件夹 (${#UPDATED_DIRS[@]} 个):${NC}"
        printf "  - %s\n" "${UPDATED_DIRS[@]}"
    fi

    # [V27] 新增：重命名文件报告
    if [ ${#RENAMED_FILES[@]} -gt 0 ]; then
        echo -e "${YELLOW}[R] 自动重命名并归档的文件 (${#RENAMED_FILES[@]} 个):${NC}"
        printf "  - %s\n" "${RENAMED_FILES[@]}"
    fi

    # [V27] 新增：清理空目录报告
    if [ ${#CLEANED_DIRS[@]} -gt 0 ]; then
        echo -e "${BLUE}[-] 清理的空文件夹 (${#CLEANED_DIRS[@]} 个):${NC}"
        # 数量太多时不全部列出，只列出前5个和总数，避免刷屏
        if [ ${#CLEANED_DIRS[@]} -gt 5 ]; then
            printf "  - %s\n" "${CLEANED_DIRS[@]:0:5}"
            echo "  - ... (以及其他 $((${#CLEANED_DIRS[@]} - 5)) 个)"
        else
             printf "  - %s\n" "${CLEANED_DIRS[@]}"
        fi
    fi

    if [ ${#unprocessed_tags[@]} -gt 0 ]; then
        echo -e "${RED}[!] 未处理的标签 (${#unprocessed_tags[@]} 个):${NC}"
        printf "  - %s\n" "${unprocessed_tags[@]}"
    else
        echo -e "${RED}[!] 未处理的标签 (0 个):${NC}"
        echo "  - (无)"
    fi
}

# ==========================================================
# 脚本主入口
# ==========================================================
main() {
    local TARGET_DIR=""
    local IS_DRY_RUN="false"
    local local_min_files=$MIN_FILES_FOR_NEW_DIR
    local local_is_recursive="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run) IS_DRY_RUN="true"; shift ;;
            -h|--help) show_usage; exit 0 ;;
            -*) log_error "未知选项: $1"; show_usage; exit 1 ;;
            *) 
                if [ -n "$TARGET_DIR" ]; then
                    log_error "只能指定一个目标目录。"
                    show_usage; exit 1
                fi
                TARGET_DIR="${1%/}"; shift ;;
        esac
    done

    if [ -z "$TARGET_DIR" ]; then
        echo -e "${GREEN}=== 漫画分类脚本 ===${NC}"
        
        while true; do
            read -rp "请输入要整理的目录: " input_dir
            TARGET_DIR="${input_dir%/}"
            [ -d "$TARGET_DIR" ] && break
            log_error "目录不存在，请重试。"
        done
        
        while true; do
            read -rp "请输入创建新文件夹的最小文件数 (默认: $local_min_files): " input_threshold
            if [ -z "$input_threshold" ]; then break; fi
            if [[ "$input_threshold" =~ ^[1-9][0-9]*$ ]]; then
                local_min_files="$input_threshold"
                break
            fi
            log_error "请输入有效的正整数。"
        done
        
        read -rp "是否扫描子文件夹? (y/n, 默认不扫描): " input_recursive
        if [[ "$input_recursive" == "y" || "$input_recursive" == "Y" ]]; then
            local_is_recursive="true"
            log_info "已开启递归扫描 (包含空目录自动清理)。"
        fi
    fi

    if [ ! -d "$TARGET_DIR" ]; then
        log_error "目录不存在: $TARGET_DIR"; exit 1
    fi

    process_directory "$TARGET_DIR" "$IS_DRY_RUN" "$local_min_files" "$local_is_recursive"
}

main "$@"
