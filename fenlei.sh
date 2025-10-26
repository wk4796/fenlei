#!/bin/bash
# [V18 修改] 彻底移除了 'set -e'
# 脚本现在将依赖内置的错误检查，以防止 I/O 错误导致脚本异常退出。

# ==========================================================
# 脚本全局配置
# ==========================================================
# 核心逻辑配置: 必须满 N 个文件才会创建 *新* 文件夹
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
# 核心处理函数 (V18 逻辑)
# ==========================================================
process_directory() {
    local TARGET_DIR="$1"
    local IS_DRY_RUN="$2"

    if [ "$IS_DRY_RUN" == "true" ]; then
        log_warn "--- 试运行模式 (DRY RUN) 已激活 ---"
        log_warn "将不会创建目录或移动任何文件。"
        echo ""
    fi
    
    declare -A file_map
    log_info "（第1轮）正在扫描目标目录并建立索引..."
    log_info "目标: $TARGET_DIR"

    # [!!! 已修复 !!!] 
    # 将原来的 "/\[*\].*" 修改为 "/\[*\]*" 
    # 以匹配像 "[英丸] ... 1.7z" 这样在 "]" 和 "." 之间有额外文本的文件。
    for file_path in "$TARGET_DIR"/\[*\]*; do
        [ -f "$file_path" ] || continue
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
        if [ -n "$tag" ]; then
            tag=$(echo "$tag" | sed -e 's|[/\\:*"<>|]||g' -e 's/\.*$//' -e 's/^\.*//')
        fi

        if [ -n "$tag" ]; then
            existing_files=${file_map["$tag"]}
            if [ -z "$existing_files" ]; then
                file_map["$tag"]="$file_path"
            else
                file_map["$tag"]="$existing_files"$'\n'"$file_path"
            fi
        fi
    done

    log_info "索引完成。"
    log_info "（第2轮）开始处理索引并移动文件..."

    local moved_count=0
    declare -a unprocessed_tags
    declare -a CREATED_DIRS=()
    declare -a UPDATED_DIRS=()
    declare -a SKIPPED_FILES=()

    for tag in "${!file_map[@]}"; do
        
        IFS=$'\n' read -r -d '' -a files < <(printf '%s\0' "${file_map["$tag"]}")
        local count=${#files[@]}
        local DEST_FOLDER="$TARGET_DIR/$tag"

        if [ "$count" -ge $MIN_FILES_FOR_NEW_DIR ] || [ -d "$DEST_FOLDER" ]; then
            
            local mkdir_needed=false
            if [ ! -d "$DEST_FOLDER" ]; then
                mkdir_needed=true
            fi

            if [ "$count" -ge $MIN_FILES_FOR_NEW_DIR ] && [ "$mkdir_needed" == "true" ]; then
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
                    # [V18] 对 mkdir 进行错误检查 (不使用 set -e)
                    mkdir -p "$DEST_FOLDER"
                    local mkdir_status=$?
                    if [ $mkdir_status -ne 0 ]; then
                        log_error "!!!! 严重错误: 创建目录 $DEST_FOLDER 失败 (可能是I/O错误) !!!!"
                        log_error "跳过此标签下的所有文件..."
                        continue # 跳到下一个 tag
                    fi
                fi
            fi
            
            for file_to_move in "${files[@]}"; do
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
                        
                        # [V18] 对 mv 进行错误检查 (不使用 set -e)
                        mv -- "$file_to_move" "$DEST_FOLDER/"
                        local mv_status=$?
                        
                        if [ $mv_status -ne 0 ]; then
                            # "mv" 失败 (例如 I/O 错误), 打印错误, 但脚本会继续
                            echo "  !!!! 错误: 移动 $filename_to_move 失败 (可能是I/O错误) !!!!"
                        else
                            # "mv" 成功
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
# 脚本主入口 (V14 逻辑)
# ==========================================================
main() {
    local TARGET_DIR=""
    local IS_DRY_RUN="false"

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

    # --- [V14] 交互式输入 (循环验证) ---
    if [ -z "$TARGET_DIR" ]; then
        echo -e "${GREEN}=== 漫画分类脚本 (交互模式) ===${NC}"
        echo -e "未指定目标目录。"
        
        while true; do
            read -rp "请输入要整理的目录: " input_dir
            TARGET_DIR="${input_dir%/}" # 获取输入并移除结尾斜杠

            if [ -z "$TARGET_DIR" ]; then
                log_error "路径不能为空，请重新输入:"
            elif [ ! -d "$TARGET_DIR" ]; then
                log_error "错误: 目标目录不存在!"
                log_error "请检查路径: $TARGET_DIR (或重新输入)"
            else
                # 路径有效, 退出循环
                break
            fi
        done
    fi

    # --- 检查路径 (此检查现在只对 *参数模式* 有效) ---
    if [ ! -d "$TARGET_DIR" ]; then
        log_error "错误: 目标目录不存在!"
        log_error "请检查路径: $TARGET_DIR"
        exit 1
    fi

    # --- 执行核心逻辑 ---
    process_directory "$TARGET_DIR" "$IS_DRY_RUN"
}

# 启动脚本
main "$@"
