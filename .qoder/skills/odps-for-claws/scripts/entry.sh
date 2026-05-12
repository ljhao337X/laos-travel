#!/bin/bash
#
# ODPSCMD 入口脚本 (entry.sh)
# 引导用户安装新的 ODPSCMD 或选择已有路径
# 同时提供公共函数供 install_*.sh source 时复用
#

set -e

# ============================================================
# 公共函数 (供 install_*.sh source 时复用)
# ============================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}----------------------------------------${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
}

# 检测 macOS 系统
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "此脚本仅适用于 macOS 系统"
        exit 1
    fi
    log_info "检测到 macOS 系统"
}

# 获取脚本所在目录
get_script_dir() {
    local DIR
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$DIR"
}

# 获取 shell 配置文件路径（无权限时回退到 ~/.odpscmd_env）
get_shell_rc_file() {
    local PREFERRED_RC
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == *"/zsh" ]]; then
        PREFERRED_RC="$HOME/.zshrc"
    else
        PREFERRED_RC="$HOME/.bash_profile"
    fi

    # 检查首选文件是否可写（不存在则检查父目录是否可写）
    if [[ -f "$PREFERRED_RC" ]]; then
        if [[ -w "$PREFERRED_RC" ]]; then
            echo "$PREFERRED_RC"
            return
        fi
    else
        # 文件不存在，检查父目录是否可写
        if [[ -w "$(dirname "$PREFERRED_RC")" ]]; then
            echo "$PREFERRED_RC"
            return
        fi
    fi

    # 无权限时回退到 ~/.odpscmd_env
    echo "$HOME/.odpscmd_env"
}

# 更新 shell 配置文件中的环境变量（ODPSCMD_BASE_DIR + PATH）
update_env_file() {
    local TARGET_DIR="$1"
    local SHELL_RC
    SHELL_RC=$(get_shell_rc_file)

    # 更新或添加 ODPSCMD_BASE_DIR 到 shell 配置文件
    if [[ -f "$SHELL_RC" ]] && grep -q "^export ODPSCMD_BASE_DIR=" "$SHELL_RC" 2>/dev/null; then
        sed -i '' "s|^export ODPSCMD_BASE_DIR=.*|export ODPSCMD_BASE_DIR=$TARGET_DIR|" "$SHELL_RC"
        log_info "已更新 ODPSCMD_BASE_DIR: $TARGET_DIR"
        # 补检 PATH 行
        if ! grep -q 'ODPSCMD_BASE_DIR/bin' "$SHELL_RC" 2>/dev/null; then
            echo 'export PATH=$ODPSCMD_BASE_DIR/bin:$PATH' >> "$SHELL_RC"
            log_info "已补充 PATH 配置"
        fi
    else
        echo "" >> "$SHELL_RC"
        echo "# ODPS" >> "$SHELL_RC"
        echo "export ODPSCMD_BASE_DIR=$TARGET_DIR" >> "$SHELL_RC"
        log_info "已添加 ODPSCMD_BASE_DIR: $TARGET_DIR"

        # 更新或添加 PATH
        if grep -q 'ODPSCMD_BASE_DIR/bin' "$SHELL_RC" 2>/dev/null; then
            log_info "PATH 配置已存在"
        else
            echo 'export PATH=$ODPSCMD_BASE_DIR/bin:$PATH' >> "$SHELL_RC"
            log_info "已添加 PATH 配置"
        fi
    fi

    log_success "环境变量已配置到 $SHELL_RC"
}

# 检查并确保 /usr/sbin 在 PATH 中（当前会话 + 持久化到 shell 配置文件）
ensure_usr_sbin_in_path() {
    local SHELL_RC
    SHELL_RC=$(get_shell_rc_file)

    # 检查当前会话
    if [[ ":$PATH:" != *":/usr/sbin:"* ]]; then
        export PATH="/usr/sbin:$PATH"
        log_info "已将 /usr/sbin 添加到当前会话 PATH"

        if ! grep -q '"/usr/sbin:\$PATH"' "$SHELL_RC" 2>/dev/null; then
            echo "" >> "$SHELL_RC"
            echo "# 系统工具路径" >> "$SHELL_RC"
            echo 'export PATH="/usr/sbin:$PATH"' >> "$SHELL_RC"
            log_info "已将 /usr/sbin 持久化到 $SHELL_RC"
        fi
    fi
}

# 标记公共函数已加载（install_*.sh 被 source 时据此跳过重复定义）
_ODPSCMD_COMMON_LOADED=1

# ODPSCMD 基础目录（可通过环境变量覆盖）
ODPSCMD_BASE_DIR="${ODPSCMD_BASE_DIR:-}"

# ============================================================
# entry.sh 专有函数
# ============================================================

# GUI 选择目录（macOS Finder 对话框）
select_dir_via_gui() {
    local PROMPT="$1"
    local START_DIR="${2:-$HOME}"

    osascript << EOF 2>/dev/null
tell application "System Events"
    activate
end tell
tell application "Finder"
    set selectedFolder to choose folder with prompt "$PROMPT" default location "$START_DIR"
    return POSIX path of selectedFolder
end tell
EOF
}

# 验证路径是否包含有效的 odpscmd
validate_odpscmd_path() {
    local BASE_DIR="$1"
    [[ -n "$BASE_DIR" && -d "$BASE_DIR" && -f "$BASE_DIR/bin/odpscmd" ]]
}

# 安装新的 ODPSCMD
install_new_odpscmd() {
    log_step "安装新的 ODPSCMD"

    local SCRIPT_DIR
    SCRIPT_DIR=$(get_script_dir)

    local DEFAULT_INSTALL_DIR
    DEFAULT_INSTALL_DIR="$HOME/.odpscmd"

    echo "请选择安装位置:"
    echo "1. 通过图形界面选择安装目录 (会自动在该目录下创建 odpscmd 子目录)"
    echo "2. 使用默认位置 ($DEFAULT_INSTALL_DIR)"
    echo ""
    read -p "> " CHOICE

    local INSTALL_DIR=""
    case $CHOICE in
        1)
            log_info "请在对话框中选择父级安装目录..."
            local SELECTED_PARENT
            SELECTED_PARENT=$(select_dir_via_gui "请选择 ODPSCMD 安装目录的父目录" "$HOME")
            if [[ -n "$SELECTED_PARENT" ]]; then
                INSTALL_DIR="${SELECTED_PARENT%/}/odpscmd"
            else
                log_warning "未选择目录，将使用默认位置"
                INSTALL_DIR="$DEFAULT_INSTALL_DIR"
            fi
            ;;
        2)
            INSTALL_DIR="$DEFAULT_INSTALL_DIR"
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac

    # 导出环境变量供安装脚本使用
    export ODPSCMD_BASE_DIR="$INSTALL_DIR"

    # 依次 source 安装脚本并调用各自的入口函数
    # （公共函数已通过 _ODPSCMD_COMMON_LOADED 标记，install 脚本会跳过重复定义）
    source "$SCRIPT_DIR/install_jre.sh"
    jre_main
    echo ""

    source "$SCRIPT_DIR/install_ncs.sh"
    ncs_main
    echo ""

    source "$SCRIPT_DIR/install_odpscmd.sh"
    odpscmd_install_main
    echo ""

    # modify_config.sh 保持独立，通过子进程运行（避免函数名冲突）
    bash "$SCRIPT_DIR/modify_config.sh"

    log_success "ODPSCMD 安装并初始化完成: $ODPSCMD_BASE_DIR"
}

# 选择已有的 ODPSCMD
select_existing_odpscmd() {
    log_step "选择已有的 ODPSCMD"

    log_info "请在对话框中选择包含 bin/odpscmd 的 ODPSCMD 目录..."
    local SELECTED_PATH
    SELECTED_PATH=$(select_dir_via_gui "请选择 ODPSCMD 安装目录" "$HOME")

    if [[ -z "$SELECTED_PATH" ]]; then
        log_error "未选择路径"
        return 1
    fi

    SELECTED_PATH="${SELECTED_PATH%/}"

    # 验证路径
    if ! validate_odpscmd_path "$SELECTED_PATH"; then
        log_error "无效路径: $SELECTED_PATH"
        log_info "请确保目录包含 bin/odpscmd 可执行文件"
        return 1
    fi

    # 导出环境变量 + 写入 shell 配置文件
    export ODPSCMD_BASE_DIR="$SELECTED_PATH"
    export PATH="$ODPSCMD_BASE_DIR/bin:$PATH"
    update_env_file "$SELECTED_PATH"

    log_success "已关联已有 ODPSCMD: $ODPSCMD_BASE_DIR"
}

# 主流程
main() {
    # 首先检查 /usr/sbin 在 PATH 中
    ensure_usr_sbin_in_path

    # 检查环境变量是否已经存在且有效
    if validate_odpscmd_path "$ODPSCMD_BASE_DIR"; then
        log_success "环境变量 ODPSCMD_BASE_DIR 已设置且有效: $ODPSCMD_BASE_DIR"
    fi

    log_step "ODPSCMD 环境初始化"

    echo "请选择操作:"
    echo "1. 安装新的 ODPSCMD"
    echo "2. 选择已有的 ODPSCMD 路径"
    echo ""
    read -p "> " CHOICE

    case $CHOICE in
        1)
            install_new_odpscmd
            ;;
        2)
            select_existing_odpscmd
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac
}

# 如果是被 source 的，则执行 main 但不 exit
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
else
    # 被 source 时执行主逻辑以初始化变量
    main
fi
