#!/bin/bash
# [V18 修改] 彻底移除了 'set -e'
# [V19 修改] (已回滚) 试图使用 \0 导致了 V22 的 bug
# [V20 修改] 交互式阈值
# [V21 修改] 移除了交互空行
# [V22 修改]
# 1. (性能) 第1轮扫描从 for 循环升级为 'find' + 'while read' 循环
# 2. (功能) 增加交互式递归选项
# [V23 修改]
# 1. [!!! 严重 BUG 修复 !!!] Bash 变量无法存储 \0, 导致 V22 中 file_map 路径被错误拼接。
# 2. (修复) 回滚 V19 的 \0 逻辑, 恢复使用 \n (换行符) 作为 file_map 和 mapfile 的分隔符。
# [V24 修改]
# 1. [!!! 语法错误修复 !!!] 修复了 V23 中引入的 'if { ... } fi' 语法错误。
# [V25 修改]
# 1. (交互) 优化了递归提示, 使其明确说明回车的默认行为。
# [V26 修改]
# 1. (交互) 根据您的要求, 进一步将 "递归" 替换为 "扫描子文件夹"。

# ==========================================================
# 脚本全局配置
# ==========================================================
# 核心逻辑配置: 必须满 N 个文件才会创建 *新* 文件夹 (这是默认值)
MIN_FILES_FOR_NEW_DIR=2

# ==========================================================
# 核心正则表达式 (V9)
# ==========================================================
RE_STEP_1='^\[([^]]+)\]'     # 匹配 [aaa] 或 [aaa(bbb)]
RE_STEP_2='\(([^)]+)\)'     # 匹配 (bbb)

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

# 帮助/用法
show_usage() {
    echo "用法: $0 [选项] [目标目录]"
    echo ""
    echo "一个根据文件名 [作者(Piro)] 或 [作者] 模式自动分类漫画的脚本。"
    echo ""
    echo "如果未提供 [目标目录]，脚本将以交互模式启动。"
    echo ""
    echo "选项:"
    echo "  -n, --dry-run    试运行。只打印将要执行的操作，不实际移动文件。"
    echo "  -h, --help       显示此帮助信息。"
}

# ==========================================================
# 核心处理函数 (V24 逻辑)
# ==========================================================
process_directory() {
    local TARGET_DIR="$1"
    local IS_DRY_RUN="$2"
    local effective_min_files="$3" # [V20]
    local IS_RECURSIVE="$4"        # [V22]

    if [ "$IS_DRY_RUN" == "true" ]; then
        log_warn "--- 试运行模式 (DRY RUN) 已激活 ---"
        log_warn "将不会创建目录或移动任何文件。"
        echo ""
    fi
    
    declare -A file_map
    # [V19] 性能优化: 缓存净化(sed)过的标签名
    declare -A tag_sanitize_cache 
    
    log_info "（第1轮）正在扫描目标目录并建立索引..."
    log_info "目标: $TARGET_DIR"
    log_info "生效阈值: $effective_min_files"
    
    # [V22] 根据 $IS_RECURSIVE 动态设置 find 命令
    local find_args=("$TARGET_DIR")
    if [ "$IS_RECURSIVE" == "true" ]; then
        log_info "扫描模式: ${GREEN}开启扫描子文件夹${NC} (将扫描所有子目录)"
    else
        log_info "扫描模式: ${RED}关闭扫描子文件夹${NC} (仅扫描顶层目录)"
        find_args+=("-maxdepth" "1")
    fi

    # [V23] 修复: 切换回 \n 分隔
    while IFS= read -r file_path; do
        
        filename=$(basename "$file_path")
        tag=""

        # 步骤 1: 提取 [ ... ] 之间的内容
        if [[ "$filename" =~ $RE_STEP_1 ]]; then
            inner_content="${BASH_REMATCH[1]}"
            
            # 步骤 2: 检查是否包含 (bbb)
            if [[ "$inner_content" =~ $RE_STEP_2 ]]; then
                tag="${BASH_REMATCH[1]}" # 规则 1: 提取 (bbb)
            else
                tag="$inner_content" # 规则 2: 使用 "aaa"
            fi
        fi

        # 步骤 3: 净化 "tag" (文件夹名称)
        # [V24] 修复: V23 'if {' 语法错误
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
                # [V23] 修复: 恢复使用 \n (换行符)
                file_map["$tag"]="$existing_files"$'\n'"$file_path"
            fi
        fi
    # [V23] 修复: 'find' 使用默认的 -print (换行符分隔)
    done < <(find "${find_args[@]}" -type f -name '\[*\]*' -print)
    # [V22] 'find' 循环结束

    log_info "索引完成。"
    log_info "（第2轮）开始处理索引并移动文件..."

    local moved_count=0
    declare -a unprocessed_tags
    declare -a CREATED_DIRS=()
    declare -a UPDATED_DIRS=()
    declare -a SKIPPED_FILES=()

    for tag in "${!file_map[@]}"; do
        
        # [V23] 修复: 移除 mapfile 的 -d '\0' 选项
        local files=()
        mapfile -t files < <(printf '%s' "${file_map["$tag"]}")
        
        local count=${#files[@]}
        local DEST_FOLDER="$TARGET_DIR/$tag"

        # [V20] 使用 $effective_min_files
        if [ "$count" -ge $effective_min_files ] || [ -d "$DEST_FOLDER" ]; then
            
            local mkdir_needed=false
            if [ ! -d "$DEST_FOLDER" ]; then
                mkdir_needed=true
            fi

            # [V20] 使用 $effective_min_files
            if [ "$count" -ge $effective_min_files ] && [ "$mkdir_needed" == "true" ]; then
                echo "处理新文件夹: $DEST_FOLDER (共 $count 个文件)"
                CREATED_DIRS+=("$tag")
            else
                echo "归档到已有文件夹: $DEST_FOLDER (共 $count 个文件)"
                UPDATED_DIRS+=("$tag")
            fi

            # [V24] 修复: V23 'if {' 语法错误
            if [ "$mkdir_needed" == "true" ]; then
                if [ "$IS_DRY_RUN" == "true" ]; then
                    log_dryrun "将创建文件夹: $DEST_FOLDER"
                else
                    mkdir -p "$DEST_FOLDER"
                    local mkdir_status=$?
                    if [ $mkdir_status -ne 0 ]; then
                        log_error "!!!! 严重错误: 创建目录 $DEST_FOLDER 失败 (可能是I/O错误) !!!!"
                        log_error "跳过此标签下的所有文件..."
                        continue
                    fi
                fi
            fi
            
            for file_to_move in "${files[@]}"; do
                [ -n "$file_to_move" ] || continue
            
                local filename_to_move=$(basename "$file_to_move")
                local dest_file_path="$DEST_FOLDER/$filename_to_move"
                
                if [ -f "$dest_file_path" ]; then
                    if [ "$IS_DRY_RUN" == "true" ]; then
                        log_dryrun "  -> 跳过 $filename_to_move (目标已存在)"
                    else
                        echo "  -> 跳过 $filename_to_move (目标已存在)"
                    fi
                    SKIPPED_FILES+=("$filename_to_move")
                else
                    if [ "$IS_DRY_RUN" == "true" ]; then
                        log_dryrun "  -> 移动 $filename_to_move 到 $DEST_FOLDER/"
                        ((moved_count++))
                    else
                        echo "  -> 移动 $filename_to_move 到 $DEST_FOLDER/"
                        
                        mv -- "$file_to_move" "$DEST_FOLDER/"
                        local mv_status=$?
                        
                        if [ $mv_status -ne 0 ]; then
                            echo "  !!!! 错误: 移动 $filename_to_move 失败 (可能是I/O错误) !!!!"
                        else
                            ((moved_count++))
                        fi
                    fi
                fi
            done
            
        else
            unprocessed_tags+=("$tag (数量: $count)")
        fi
    done

    echo "------------------------------"
    log_info "操作完成。共移动 $moved_count 个文件。"

    # [V15] 增强的最终报告
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

    if [ ${#SKIPPED_FILES[@]} -gt 0 ]; then
        echo -e "${YELLOW}[!] 因目标已存在而跳过的文件 (${#SKIPPED_FILES[@]} 个):${NC}"
        printf "  - %s\n" "${SKIPPED_FILES[@]}"
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
# 脚本主入口 (V26 逻辑)
# ==========================================================
main() {
    local TARGET_DIR=""
    local IS_DRY_RUN="false"
    
    # [V20]
    local local_min_files=$MIN_FILES_FOR_NEW_DIR
    # [V22]
    local local_is_recursive="false"

    # --- 参数解析 ---
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                IS_DRY_RUN="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "未知选项: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -n "$TARGET_DIR" ]; then
                    log_error "只能指定一个目标目录。"
                    show_usage
                    exit 1
                fi
                TARGET_DIR="${1%/}"
                shift
                ;;
        esac
    done

    # --- [V26] 增强的交互式输入 ---
    if [ -z "$TARGET_DIR" ]; then
        echo -e "${GREEN}=== 漫画分类脚本 (交互模式) ===${NC}"
        echo -e "未指定目标目录。"
        
        # 1. 循环获取有效目录
        while true; do
            read -rp "请输入要整理的目录: " input_dir
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
        
        # [V21] 移除了这里的 echo "" 
        
        # [V20] 2. 循环获取有效的阈值
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
        
        # [V26] 3. 询问是否扫描子文件夹 (清晰版)
        read -rp "是否扫描子文件夹? (输入 'y' 开启，按回车键默认关闭): " input_recursive
        if [[ "$input_recursive" == "y" || "$input_recursive" == "Y" ]]; then
            local_is_recursive="true"
            log_info "扫描子文件夹已${GREEN}开启${NC}。"
        else
            log_info "扫描子文件夹已${RED}关闭${NC} (默认)。"
        fi
        
        
    fi # 结束交互模式 (if [ -z "$TARGET_DIR" ])

    # --- 检查路径 ---
    if [ ! -d "$TARGET_DIR" ]; then
        log_error "错误: 目标目录不存在!"
        log_error "请检查路径: $TARGET_DIR"
        exit 1
    fi

    # --- 执行核心逻辑 ---
    # [V22]
    process_directory "$TARGET_DIR" "$IS_DRY_RUN" "$local_min_files" "$local_is_recursive"
}

# 启动脚本
main "$@"
