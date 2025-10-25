cat > ~/fenlei.sh << 'EOF'
#!/bin/bash
set -e # 模仿 bf.sh，任何命令失败立即退出

# ==========================================================
# 脚本全局配置 (模仿 bf.sh 顶部配置区)
# ==========================================================

# 1. 默认设置 (方案一：交互式)
DEFAULT_TARGET_DIR="/xiazai/rclone/移动云盘/漫画/h/mi"

# 2. 核心逻辑配置 (方案三：提取魔法数字)
MIN_FILES_FOR_NEW_DIR=2

# ==========================================================
# V10 的核心正则表达式 (保持不变)
# ==========================================================
RE_STEP_1='^\[([^]]+)\]'     # 匹配 [aaa] 或 [aaa(bbb)]
RE_STEP_2='\(([^)]+)\)'     # 匹配 (bbb)

# ==========================================================
# 辅助函数 (模仿 bf.sh)
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
log_dryrun() { echo -e "${BLUE}[试运行]${NC} $1"; } # (方案二：DryRun)

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
# 核心处理函数 (V12 逻辑)
# ==========================================================
process_directory() {
    local TARGET_DIR="$1"
    local IS_DRY_RUN="$2"

    if [ "$IS_DRY_RUN" == "true" ]; then
        log_warn "--- 试运行模式 (DRY RUN) 已激活 ---"
        log_warn "将不会创建目录或移动任何文件。"
        echo ""
    fi
    
    # 1. 声明一个关联数组 (哈希表)
    declare -A file_map

    log_info "（第1轮）正在扫描目标目录并建立索引..."
    log_info "目标: $TARGET_DIR"

    # 遍历 *指定目录* 下所有符合 '[*]*. ' 模式的文件
    for file_path in "$TARGET_DIR"/\[*\].*; do
        [ -f "$file_path" ] || continue
        filename=$(basename "$file_path")
        tag=""

        # 步骤 1: 绝对严格地只提取 *第一个* [ ... ] 之间的内容
        if [[ "$filename" =~ $RE_STEP_1 ]]; then
            inner_content="${BASH_REMATCH[1]}"
            
            # 步骤 2: 检查这个 inner_content 是否包含 (bbb) 格式
            if [[ "$inner_content" =~ $RE_STEP_2 ]]; then
                tag="${BASH_REMATCH[1]}" # 规则 1 命中: 提取 (bbb)
            else
                tag="$inner_content" # 规则 2 命中: 使用 "aaa"
            fi
        fi

        # =========================================================================
        # *** [新功能 V12 - 已应用方案一] ***
        # 步骤 3: 净化 "tag" (文件夹名称), 移除所有无效字符
        if [ -n "$tag" ]; then
            # 1. 移除 / \ : * ? " < > |
            # 2. 移除结尾的一个或多个 . (例如 "Artist." -> "Artist")
            # 3. 移除开头的一个或多个 . (防止创建隐藏文件夹)
            tag=$(echo "$tag" | sed -e 's|[/\\:*"<>|]||g' -e 's/\.*$//' -e 's/^\.*//')
        fi
        # =========================================================================

        # 如果成功提取到标签 ( "bbb" 或 "aaa" )
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

    # 遍历所有被索引的标签
    for tag in "${!file_map[@]}"; do
        
        IFS=$'\n' read -r -d '' -a files < <(printf '%s\0' "${file_map["$tag"]}")
        local count=${#files[@]}
        local DEST_FOLDER="$TARGET_DIR/$tag"

        # V10 核心逻辑:
        if [ "$count" -ge $MIN_FILES_FOR_NEW_DIR ] || [ -d "$DEST_FOLDER" ]; then
            
            local mkdir_needed=false
            if [ ! -d "$DEST_FOLDER" ]; then
                mkdir_needed=true
            fi

            # 打印提示语
            if [ "$count" -ge $MIN_FILES_FOR_NEW_DIR ] && [ "$mkdir_needed" == "true" ]; then
                echo "处理新文件夹: $DEST_FOLDER (共 $count 个文件)"
            else
                echo "归档到已有文件夹: $DEST_FOLDER (共 $count 个文件)"
            fi

            # [方案二：DryRun] 检查是否需要创建文件夹
            if [ "$mkdir_needed" == "true" ]; then
                if [ "$IS_DRY_RUN" == "true" ]; then
                    log_dryrun "将创建文件夹: $DEST_FOLDER"
                else
                    mkdir -p "$DEST_FOLDER"
                fi
            fi
            
            # 遍历这个数组并移动所有文件
            for file_to_move in "${files[@]}"; do
                local filename_to_move=$(basename "$file_to_move")
                
                # [方案二：DryRun] 检查移动操作
                if [ "$IS_DRY_RUN" == "true" ]; then
                    log_dryrun "  -> 移动 $filename_to_move 到 $DEST_FOLDER/"
                    ((moved_count++)) # 在试运行时也计数，使报告准确
                else
                    echo "  -> 移动 $filename_to_move 到 $DEST_FOLDER/"
                    mv -- "$file_to_move" "$DEST_FOLDER/"
                    if [ $? -ne 0 ]; then
                        echo "  !!!! 错误: 移动 $filename_to_move 失败 (可能是I/O错误) !!!!"
                    else
                        ((moved_count++))
                    fi
                fi
            done
            
        else
            # 数量不足 (count=1) 且 文件夹不存在, 记录下来
            unprocessed_tags+=("$tag (数量: $count)")
        fi
    done

    echo "------------------------------"
    log_info "操作完成。共移动 $moved_count 个文件。"

    echo "---"
    echo "以下标签因文件数量不足($MIN_FILES_FOR_NEW_DIR)个且文件夹不存在而未被处理:"
    if [ ${#unprocessed_tags[@]} -eq 0 ]; then
        echo "  (无)"
    else
        for item in "${unprocessed_tags[@]}"; do
            echo "  - $item"
        done
    fi
}

# ==========================================================
# 脚本主入口 (模仿 bf.sh 的 main)
# ==========================================================
main() {
    local TARGET_DIR=""
    local IS_DRY_RUN="false"

    # --- 方案一：参数解析 ---
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run) # (方案二：DryRun)
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
                # 假设这是目标目录
                if [ -n "$TARGET_DIR" ]; then
                    log_error "只能指定一个目标目录。"
                    show_usage
                    exit 1
                fi
                # 移除路径末尾的斜杠(如果存在)
                TARGET_DIR="${1%/}"
                shift
                ;;
        esac
    done

    # --- 方案一：交互式输入 ---
    if [ -z "$TARGET_DIR" ]; then
        echo -e "${GREEN}=== 漫画分类脚本 (交互模式) ===${NC}"
        echo -e "未指定目标目录。"
        read -rp "请输入要整理的目录 (默认为: $DEFAULT_TARGET_DIR): " input_dir
        TARGET_DIR="${input_dir:-$DEFAULT_TARGET_DIR}"
        # 再次移除路径末尾的斜杠
        TARGET_DIR="${TARGET_DIR%/}"
    fi

    # --- 检查路径 ---
    if [ ! -d "$TARGET_DIR" ]; then
        log_error "错误: 目标目录不存在!"
        log_error "请检查路径: $TARGET_DIR"
        exit 1
    fi

    # --- 执行核心逻辑 ---
    process_directory "$TARGET_DIR" "$IS_DRY_RUN"
}

# 启动脚本 (模仿 bf.sh)
main "$@"
EOF
