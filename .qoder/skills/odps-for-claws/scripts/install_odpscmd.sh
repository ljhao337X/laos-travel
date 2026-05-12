#!/bin/bash
#
# Author: zhiwei
# ODPSCMD 安装脚本
# 下载并安装 ODPS 命令行工具
#
# 可被 entry.sh source 调用，也可独立运行
#

set -e

# ============================================================
# 公共函数（当未被 entry.sh source 时独立定义）
# ============================================================
if [[ -z "${_ODPSCMD_COMMON_LOADED:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'

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

    check_macos() {
        if [[ "$OSTYPE" != "darwin"* ]]; then
            log_error "此脚本仅适用于 macOS 系统"
            exit 1
        fi
        log_info "检测到 macOS 系统"
    }

    get_script_dir() {
        local DIR
        DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        echo "$DIR"
    }

    # 获取 shell 配置文件路径（独立运行时使用；被 source 时 entry.sh 的版本会覆盖）
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
fi

# ============================================================
# ODPSCMD 安装专有函数
# ============================================================

# ODPSCMD 基础目录（可通过环境变量覆盖）
ODPSCMD_BASE_DIR="${ODPSCMD_BASE_DIR:-}"

# 获取 ODPSCMD 安装目录
get_odpscmd_dir() {
    if [[ -n "$ODPSCMD_BASE_DIR" ]]; then
        echo "$ODPSCMD_BASE_DIR"
    else
        echo "$HOME/.odpscmd"
    fi
}

# 检测架构
detect_odpscmd_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        arm64)
            log_info "架构：Apple Silicon (arm64)"
            ;;
        x86_64)
            log_info "架构：Intel (x86_64)"
            ;;
        *)
            log_error "不支持的架构：$ARCH"
            exit 1
            ;;
    esac
}

# 检测是否已安装 ODPSCMD
check_odpscmd() {
    if command -v odpscmd &> /dev/null; then
        log_success "ODPSCMD 已安装"
        log_info "路径：$(which odpscmd)"
        return 0
    else
        log_warning "未检测到 ODPSCMD"
        return 1
    fi
}

# 下载并安装 ODPSCMD
install_odpscmd() {
    log_info "下载并安装 ODPSCMD..."

    local DOWNLOAD_URL="http://odps.alibaba-inc.com/official_downloads/odpscmd/latest/odps_clt_release_64.tar.gz"
    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    log_info "下载链接：$DOWNLOAD_URL"

    # 下载 ODPSCMD
    if command -v curl &> /dev/null; then
        local HTTP_CODE
        HTTP_CODE=$(curl -L -o "$TEMP_FILE" -w "%{http_code}" "$DOWNLOAD_URL" --progress-bar)
        if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
            log_error "下载失败，HTTP 状态码: ${HTTP_CODE}"
            rm -f "$TEMP_FILE"
            exit 1
        fi
    elif command -v wget &> /dev/null; then
        wget -O "$TEMP_FILE" "$DOWNLOAD_URL" --show-progress
    else
        log_error "未找到 curl 或 wget，无法下载"
        rm -f "$TEMP_FILE"
        exit 1
    fi

    if [[ ! -f "$TEMP_FILE" ]]; then
        log_error "下载失败"
        rm -f "$TEMP_FILE"
        exit 1
    fi

    log_success "下载完成：$TEMP_FILE"

    # 确定安装目录
    local INSTALL_DIR
    INSTALL_DIR=$(get_odpscmd_dir)
    log_info "安装 ODPSCMD 到 $INSTALL_DIR..."

    # 清理旧版本
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    # 解压
    log_info "解压 ODPSCMD..."
    tar -xzf "$TEMP_FILE" -C "$INSTALL_DIR"

    # 清理临时文件
    rm -f "$TEMP_FILE"

    # 获取解压后的目录名（通常是 odps_clt_release_64）
    local EXTRACTED_DIR
    EXTRACTED_DIR=$(ls "$INSTALL_DIR")
    if [[ -d "$INSTALL_DIR/$EXTRACTED_DIR" ]]; then
        mv "$INSTALL_DIR/$EXTRACTED_DIR"/* "$INSTALL_DIR/"
        rm -rf "$INSTALL_DIR/$EXTRACTED_DIR"
    fi


    # 检查 bin/odpscmd 可执行文件
    local ODPSCMD_BIN="$INSTALL_DIR/bin/odpscmd"

    if [[ ! -f "$ODPSCMD_BIN" ]]; then
        log_error "未找到 $ODPSCMD_BIN 可执行文件"
        exit 1
    fi

    local CHMOD_CMD="chmod"
    command -v chmod &> /dev/null || CHMOD_CMD="/bin/chmod"
    $CHMOD_CMD +x "$ODPSCMD_BIN"

    log_success "ODPSCMD 安装完成"
}

# 配置环境变量（调用 update_env_file + 导出到当前会话）
# 参数 $1: 可选，指定 ODPSCMD 安装目录，不传则使用 get_odpscmd_dir
setup_odpscmd_env() {
    log_info "配置环境变量..."

    local INSTALL_DIR
    if [[ -n "${1:-}" ]]; then
        INSTALL_DIR="$1"
    else
        INSTALL_DIR=$(get_odpscmd_dir)
    fi

    update_env_file "$INSTALL_DIR"

    # 导出到当前会话
    export ODPSCMD_BASE_DIR="$INSTALL_DIR"
    export PATH="$ODPSCMD_BASE_DIR/bin:$PATH"
}

# 生成默认配置文件
generate_default_config() {
    local INSTALL_DIR
    INSTALL_DIR=$(get_odpscmd_dir)
    local CONFIG_FILE="$INSTALL_DIR/conf/odps_config.ini"

    log_info "生成默认配置文件..."

    cat > "$CONFIG_FILE" << 'EOF'
project_name=$PROJECT_NAME
account_provider=external
processCommand=$PROCESS_COMMAND
processCommandTimeout=20

# this endpoint is for production environment
end_point=$END_POINT

# this url is for odpscmd update
update_url=http://odps.alibaba-inc.com/official_downloads

# download sql results by instance tunnel
use_instance_tunnel=true

# the max records when download sql results by instance tunnel
instance_tunnel_max_record=10000

# use set.<key>=<value> to set flags when console launched
# e.g. set.odps.sql.select.output.format=csv
EOF

    log_success "默认配置文件已生成: $CONFIG_FILE"
}

# 验证安装
verify_odpscmd() {
    log_info "验证 ODPSCMD 安装..."

    if command -v odpscmd &> /dev/null; then
        log_success "✓ ODPSCMD 可用"
        log_info "路径：$(which odpscmd)"
        log_info "版本：$(odpscmd -v 2>&1 || echo '无法获取版本信息')"
        return 0
    else
        log_warning "✗ ODPSCMD 不可用"
        return 1
    fi
}

# 主函数
odpscmd_install_main() {
    # 首先检查 /usr/sbin 在 PATH 中
    ensure_usr_sbin_in_path

    echo "========================================"
    echo "    STEP 3/4: ODPSCMD 安装脚本 START"
    echo "========================================"
    echo ""

    log_warning "安装过程中需要管理员权限，可能会提示输入解锁屏幕的密码"
    echo ""

    check_macos
    detect_odpscmd_arch
    echo ""

    # 检查是否已安装
    if verify_odpscmd; then
        # 已安装，通过 which 找到实际路径并配置环境变量
        local EXISTING_ODPSCMD
        EXISTING_ODPSCMD=$(which odpscmd)
        # 如果是软连接，获取真实路径（macOS 兼容写法）
        if [[ -L "$EXISTING_ODPSCMD" ]]; then
            EXISTING_ODPSCMD=$(cd "$(dirname "$EXISTING_ODPSCMD")" && pwd -P)/$(basename "$EXISTING_ODPSCMD")
        fi
        # 获取 odpscmd 所在目录的父目录（即 ODPSCMD_BASE_DIR）
        local EXISTING_DIR
        EXISTING_DIR=$(dirname "$(dirname "$EXISTING_ODPSCMD")")
        log_info "检测到已安装的 ODPSCMD: $EXISTING_DIR"
        setup_odpscmd_env "$EXISTING_DIR"
        echo ""
    else
        install_odpscmd
        echo ""

        generate_default_config
        echo ""

        setup_odpscmd_env
        echo ""

        verify_odpscmd
        echo ""
    fi

    echo "========================================"
    echo "    STEP 3/4: ODPSCMD 安装脚本 END"
    echo "========================================"
}

# 独立运行时执行主函数；被 source 时仅加载函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    odpscmd_install_main "$@"
fi
