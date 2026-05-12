#!/bin/bash
#
# Author: zhiwei
# JRE 安装脚本
# 下载并安装 Java 运行环境
# 支持两种安装方式：
# 1. 通过 Homebrew 安装（优先，带国内镜像）
# 2. 通过下 Adoptium 安装
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
# JRE 安装专有函数
# ============================================================

# Java 版本
JAVA_MAJOR_VERSION=17

# 检测系统架构，设置 Adoptium API 所需的架构标识
detect_jre_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        arm64)
            log_info "架构：Apple Silicon (arm64)"
            ADOPTIUM_ARCH="aarch64"
            ;;
        x86_64)
            log_info "架构：Intel (x86_64)"
            ADOPTIUM_ARCH="x64"
            ;;
        *)
            log_error "不支持的架构：$ARCH"
            exit 1
            ;;
    esac
}

# 检测 Homebrew
check_brew() {
    if command -v brew &> /dev/null; then
        log_success "检测到 Homebrew"
        log_info "版本：$(brew --version | head -n 1)"
        return 0
    else
        log_warning "未检测到 Homebrew"
        return 1
    fi
}

# 配置 Homebrew 国内镜像
setup_brew_mirror() {
    log_info "配置 Homebrew 国内镜像（中科大源）..."
 
    export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
    export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
    export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
 
    brew update
 
    log_success "Homebrew 镜像配置完成"
}

# 使用 Homebrew 安装 JDK
install_with_brew() {
    log_info "使用 Homebrew 安装 OpenJDK ${JAVA_MAJOR_VERSION}..."

    setup_brew_mirror

    # 检查是否已通过 brew 安装
    if brew list "openjdk@${JAVA_MAJOR_VERSION}" &> /dev/null; then
        log_info "openjdk@${JAVA_MAJOR_VERSION} 已通过 Homebrew 安装，跳过安装步骤"
    else
        log_info "正在安装 openjdk@${JAVA_MAJOR_VERSION}..."
        brew install "openjdk@${JAVA_MAJOR_VERSION}"
    fi

    log_success "OpenJDK ${JAVA_MAJOR_VERSION} 安装完成"

    local JDK_PATH
    JDK_PATH=$(brew --prefix "openjdk@${JAVA_MAJOR_VERSION}")
    export JAVA_HOME="${JDK_PATH}/libexec/openjdk.jdk/Contents/Home"
    export PATH="$JAVA_HOME/bin:$PATH"

    log_info "JAVA_HOME: $JAVA_HOME"
    log_success "Java 已加入当前会话 PATH"
}

# 通过 Adoptium API 下载并安装 JRE
install_with_adoptium() {
    log_info "通过 Adoptium API 下载 Eclipse Temurin JRE ${JAVA_MAJOR_VERSION}..."

    # 构造 Adoptium API 下载 URL（image_type=jre 仅下载运行时，体积更小）
    # 文档: https://api.adoptium.net/q/swagger-ui/
    local DOWNLOAD_URL="https://api.adoptium.net/v3/binary/latest/${JAVA_MAJOR_VERSION}/ga/mac/${ADOPTIUM_ARCH}/jre/hotspot/normal/eclipse"
    log_info "下载地址: ${DOWNLOAD_URL}"

    local TEMP_DIR
    TEMP_DIR=$(mktemp -d)
    local TAR_PATH="${TEMP_DIR}/temurin-jre.tar.gz"

    # 下载 JRE 压缩包
    log_info "正在下载 JRE..."
    if command -v curl &> /dev/null; then
        local HTTP_CODE
        HTTP_CODE=$(curl -L -o "$TAR_PATH" -w "%{http_code}" "$DOWNLOAD_URL" --progress-bar)
        if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
            log_error "下载失败，HTTP 状态码: ${HTTP_CODE}"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    elif command -v wget &> /dev/null; then
        wget -O "$TAR_PATH" "$DOWNLOAD_URL" --show-progress
    else
        log_error "未找到 curl 或 wget，无法下载"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    if [[ ! -f "$TAR_PATH" ]]; then
        log_error "下载失败"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    log_success "下载完成: ${TAR_PATH}"

    # 解压到本地安装目录（无需 sudo）
    local INSTALL_DIR
    INSTALL_DIR="$HOME/.jdks"
    mkdir -p "$INSTALL_DIR"

    log_info "解压 JRE..."
    tar -xzf "$TAR_PATH" -C "$INSTALL_DIR"

    # 找到解压后的 JRE 目录（目录名形如 jdk-17.x.x+y-jre）
    local JRE_DIR
    JRE_DIR=$(find "$INSTALL_DIR" -maxdepth 1 -type d -name "jdk-${JAVA_MAJOR_VERSION}*-jre" | sort -V | tail -n 1)

    # 兼容：部分版本目录名可能不带 -jre 后缀
    if [[ -z "$JRE_DIR" ]]; then
        JRE_DIR=$(find "$INSTALL_DIR" -maxdepth 1 -type d -name "jdk-${JAVA_MAJOR_VERSION}*" | sort -V | tail -n 1)
    fi

    if [[ -z "$JRE_DIR" ]]; then
        log_error "解压后未找到 JRE 目录"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # macOS 的 Adoptium tar.gz 解压后包含 Contents/Home 结构
    if [[ -d "${JRE_DIR}/Contents/Home" ]]; then
        export JAVA_HOME="${JRE_DIR}/Contents/Home"
    else
        export JAVA_HOME="${JRE_DIR}"
    fi

    # 确保 java 可执行
    local CHMOD_CMD="chmod"
    command -v chmod &> /dev/null || CHMOD_CMD="/bin/chmod"
    $CHMOD_CMD +x "$JAVA_HOME/bin/java" 2>/dev/null || true

    export PATH="$JAVA_HOME/bin:$PATH"

    # 清理临时文件
    rm -rf "$TEMP_DIR"

    log_success "Eclipse Temurin JRE ${JAVA_MAJOR_VERSION} 安装完成"
    log_info "安装位置: ${JRE_DIR}"
    log_info "JAVA_HOME: ${JAVA_HOME}"
}

# 配置 Java 环境变量
setup_jre_env() {
    log_info "配置 Java 环境变量..."

    local SHELL_RC
    SHELL_RC=$(get_shell_rc_file)

    local JAVA_HOME_PATH=""

    # 优先使用当前会话中已设置的 JAVA_HOME（刚安装的）
    if [[ -n "${JAVA_HOME:-}" ]] && [[ -x "${JAVA_HOME}/bin/java" ]]; then
        JAVA_HOME_PATH="$JAVA_HOME"
    else
        JAVA_HOME_PATH=$(/usr/libexec/java_home 2>/dev/null || echo "")
    fi

    if [[ -z "$JAVA_HOME_PATH" ]]; then
        log_warning "未找到 JAVA_HOME，可能需要手动配置"
        return 1
    fi

    # 判断是 brew 安装还是 Adoptium 安装，写入不同的环境变量
    local JAVA_HOME_EXPR
    if [[ "$JAVA_HOME_PATH" == *"Cellar"* ]] || [[ "$JAVA_HOME_PATH" == *"homebrew"* ]]; then
        # brew 安装：使用 /usr/libexec/java_home 动态获取
        JAVA_HOME_EXPR='$(/usr/libexec/java_home)'
    else
        # Adoptium 安装：写入固定路径
        JAVA_HOME_EXPR="$JAVA_HOME_PATH"
    fi

    # 更新或添加 JAVA_HOME 到 shell 配置文件
    if [[ -f "$SHELL_RC" ]] && grep -q "^export JAVA_HOME=" "$SHELL_RC" 2>/dev/null; then
        sed -i '' "s|^export JAVA_HOME=.*|export JAVA_HOME=${JAVA_HOME_EXPR}|" "$SHELL_RC"
        log_info "已更新 JAVA_HOME: ${JAVA_HOME_EXPR}"
        # 补检 PATH 行
        if ! grep -q 'JAVA_HOME/bin' "$SHELL_RC" 2>/dev/null; then
            echo 'export PATH=$JAVA_HOME/bin:$PATH' >> "$SHELL_RC"
            log_info "已补充 PATH 配置"
        fi
    else
        echo "" >> "$SHELL_RC"
        echo "# Java" >> "$SHELL_RC"
        echo "export JAVA_HOME=${JAVA_HOME_EXPR}" >> "$SHELL_RC"
        log_info "已添加 JAVA_HOME: ${JAVA_HOME_EXPR}"

        # 更新或添加 PATH
        if grep -q 'JAVA_HOME/bin' "$SHELL_RC" 2>/dev/null; then
            log_info "PATH 配置已存在"
        else
            echo 'export PATH=$JAVA_HOME/bin:$PATH' >> "$SHELL_RC"
            log_info "已添加 PATH 配置"
        fi
    fi

    # 导出到当前会话
    export JAVA_HOME="$JAVA_HOME_PATH"
    export PATH="$JAVA_HOME/bin:$PATH"

    log_success "Java 环境变量已配置到 $SHELL_RC"
}

# 验证安装
verify_jre() {
    log_info "验证 Java 安装..."

    if command -v java &> /dev/null && java -version &> /dev/null; then
        log_success "✓ Java 可用"
        log_info "版本：$(java -version 2>&1 | head -n 1 || echo '无法获取版本信息')"
        log_info "路径：$(which java)"
        return 0
    else
        log_warning "✗ Java 不可用"
        return 1
    fi
}

# 主函数
jre_main() {
    # 首先检查 /usr/sbin 在 PATH 中
    ensure_usr_sbin_in_path

    echo "========================================"
    echo "    STEP 1/4: JRE 安装脚本 START"
    echo "========================================"
    echo ""

    log_warning "安装过程中需要管理员权限，可能会提示输入解锁屏幕的密码"
    echo ""

    check_macos
    detect_jre_arch
    echo ""

    # 检查是否已安装
    if verify_jre; then
        echo ""
    else
        # 选择安装方式：优先 brew，备选 Adoptium API
        if check_brew; then
            install_with_brew
        else
            install_with_adoptium
        fi
        echo ""

        setup_jre_env
        echo ""

        verify_jre
        echo ""
    fi

    echo "========================================"
    echo "    STEP 1/4: JRE 安装脚本 END"
    echo "========================================"
}

# 独立运行时执行主函数；被 source 时仅加载函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    jre_main "$@"
fi
