#!/bin/bash
# [V28 修改]
# 1. (交互优化) 在目录输入阶段增加 'q' 退出功能。
# --- V27 继承功能 ---
# 2. (核心增强) 自动重命名策略 (_v1, _v2...)。
# 3. (报告增强) 总结报告增加重命名列表。
# 4. (清理功能) 清理空目录。
# 5. (底层修复) print0/read -d '' 完美文件名支持。

# ==========================================================
# 脚本全局配置
# ==========================================================
MIN_FILES_FOR_NEW_DIR=2

# ==========================================================
# 核心正则表达式
# ==========================================================
RE_STEP_1='^\s*\[([^]]+)\]'  # 匹配 [aaa] 或 [aaa(bbb)]
RE_STEP_2='\(([^)]+)\)'      # 匹配 (bbb)

# ==========================================================
# 辅助函数
# ==========================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_dryrun() { echo -e "${BLUE}[试运行]${NC} $1"; }

# 获取唯一文件名 (处理重名)
get_unique_filename() {
    local dir="$1"
    local filename="$2"
    
    if [ ! -e "$dir/$filename" ]; then
        echo "$filename"
        return
    fi

    local extension="${filename##*.}"
    local filename_no_ext="${filename%.*}"
    local counter=1

    if [ "$filename" == "$extension" ]; then
        extension=""
        filename_no_ext="$filename"
    else
        extension=".$extension"
    fi

    while true; do
        local new_name="${filename_no_ext}_v${counter}${extension}"
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
# 核心处理函数
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
    
    declare -A file_map
    declare -A tag_sanitize_cache 
    
    log_info "（第1轮）正在扫描目标目录并建立索引..."
    log_info "目标: $TARGET_DIR"
    
    local find_args=("$TARGET_DIR")
    if [ "$IS_RECURSIVE" == "false" ]; then
        find_args+=("-maxdepth" "1")
    fi
    
    while IFS= read -r -d '' file_path; do
        filename=$(basename "$file_path")
        tag=""
        if [[ "$filename" =~ $RE_STEP_1 ]]; then
            inner_content="${BASH_REMATCH[1]}"
            if [[ "$inner_content" =~ $RE_STEP_2 ]]; then
                tag="${BASH_REMATCH[1]}"
            else
                tag="$inner_content"
            fi
        fi
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
        if [ -n "$tag" ]; then
            existing_files=${file_map["$tag"]}
            if [ -z "$existing_files" ]; then
                file_map["$tag"]="$file_path"
            else
                file_map["$tag"]="$existing_files"$'\n'"$file_path"
            fi
        fi
    done < <(find "${find_args[@]}" -type f -name '*\[*\]*' -print0)

    log_info "索引完成。"
    log_info "（第2轮）开始处理索引并移动文件..."

    local moved_count=0
    declare -a unprocessed_tags
    declare -a CREATED_DIRS=()
    declare -a UPDATED_DIRS=()
    declare -a RENAMED_FILES=()
    declare -a CLEANED_DIRS=()

    for tag in "${!file_map[@]}"; do
        local files=()
        mapfile -t files < <(printf '%s' "${file_map["$tag"]}")
        
        local count=${#files[@]}
        local DEST_FOLDER="$TARGET_DIR/$tag"
        local mkdir_needed=false
        local process_group=false

        if [ -d "$DEST_FOLDER" ]; then
            process_group=true
        elif [ "$count" -ge $effective_min_files ]; then
            process_group=true
            mkdir_needed=true
        fi

        if [ "$process_group" == "true" ]; then
            if [ "$mkdir_needed" == "true" ]; then
                echo "处理新文件夹: $DEST_FOLDER (共 $count 个文件)"
                CREATED_DIRS+=("$tag")
            else
                echo "归档到已有文件夹: $DEST_FOLDER (共 $count 个文件)"
                UPDATED_DIRS+=("$tag")
            fi

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
            
            for file_to_move in "${files[@]}"; do
                [ -n "$file_to_move" ] || continue
                local filename_to_move=$(basename "$file_to_move")
                local final_filename="$filename_to_move"
                local dest_file_path="$DEST_FOLDER/$final_filename"

                if [ "$IS_DRY_RUN" == "true" ]; then
                    if [ -f "$dest_file_path" ]; then
                         log_dryrun "  -> [重命名] $filename_to_move -> (自动计算) -> $DEST_FOLDER/"
                    else
                         log_dryrun "  -> 移动 $filename_to_move 到 $DEST_FOLDER/"
                    fi
                    ((moved_count++))
                else
                    if [ -e "$dest_file_path" ]; then
                        final_filename=$(get_unique_filename "$DEST_FOLDER" "$filename_to_move")
                        dest_file_path="$DEST_FOLDER/$final_filename"
                        RENAMED_FILES+=("$filename_to_move -> $final_filename (在 [$tag] 中)")
                        echo "  -> [重命名] $filename_to_move -> $final_filename"
                    else
                        echo "  -> 移动 $filename_to_move"
                    fi
                    
                    mv -- "$file_to_move" "$dest_file_path"
                    if [ $? -eq 0 ]; then ((moved_count++)); else log_error "  移动失败: $file_to_move"; fi
                fi
            done
        else
            unprocessed_tags+=("$tag (数量: $count)")
        fi
    done

    if [ "$IS_RECURSIVE" == "true" ] && [ "$IS_DRY_RUN" == "false" ]; then
        echo ""
        log_info "（第3轮）正在清理扫描留下的空目录..."
        while IFS= read -r -d '' empty_dir; do
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

    if [ ${#RENAMED_FILES[@]} -gt 0 ]; then
        echo -e "${YELLOW}[R] 自动重命名并归档的文件 (${#RENAMED_FILES[@]} 个):${NC}"
        printf "  - %s\n" "${RENAMED_FILES[@]}"
    fi

    if [ ${#CLEANED_DIRS[@]} -gt 0 ]; then
        echo -e "${BLUE}[-] 清理的空文件夹 (${#CLEANED_DIRS[@]} 个):${NC}"
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
        echo -e "未指定目标目录。"
        
        # 1. 循环获取有效目录 (含 q 退出)
        while true; do
            read -rp "请输入要整理的目录 (输入 q 退出): " input_dir
            
            # [V28] 检查退出指令
            if [[ "$input_dir" == "q" || "$input_dir" == "Q" ]]; then
                echo "操作已取消。"
                exit 0
            fi

            TARGET_DIR="${input_dir%/}"

            if [ -z "$TARGET_DIR" ]; then
                log_error "路径不能为空，请重新输入:"
            elif [ ! -d "$TARGET_DIR" ]; then
                log_error "错误: 目标目录不存在!"
                log_error "请检查路径: $TARGET_DIR (或重新输入)"
            else
                break
            fi
        done
        
        # 2. 循环获取有效的阈值
        while true; do
            read -rp "请输入创建新文件夹的最小文件数 (默认: $local_min_files): " input_threshold
            local re_valid_int='^[1-9][0-9]*$' 

            if [ -z "$input_threshold" ]; then
                log_info "使用默认阈值: $local_min_files"
                break
            elif [[ "$input_threshold" =~ $re_valid_int ]]; then
                local_min_files="$input_threshold"
                log_info "本次运行阈值已设置为: $local_min_files"
                break
            else
                log_error "输入无效。请输入一个大于 0 的整数，或直接按回车使用默认值。"
            fi
        done
        
        # 3. 询问是否扫描子文件夹
        read -rp "是否扫描子文件夹? (输入 'y' 开启，按回车键默认关闭): " input_recursive
        if [[ "$input_recursive" == "y" || "$input_recursive" == "Y" ]]; then
            local_is_recursive="true"
            log_info "扫描子文件夹已${GREEN}开启${NC} (含空目录自动清理)。"
        else
            log_info "扫描子文件夹已${RED}关闭${NC} (默认)。"
        fi
    fi

    if [ ! -d "$TARGET_DIR" ]; then
        log_error "错误: 目标目录不存在!"
        log_error "请检查路径: $TARGET_DIR"
        exit 1
    fi

    process_directory "$TARGET_DIR" "$IS_DRY_RUN" "$local_min_files" "$local_is_recursive"
}

main "$@"
