#!/bin/bash
#
# ODPSCMD 配置文件修改脚本
# 交互式配置 odps_config.ini
#

set -e

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

# ODPSCMD 基础目录（可通过环境变量覆盖）
ODPSCMD_BASE_DIR="${ODPSCMD_BASE_DIR:-}"

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

# 获取 ODPSCMD 基础目录（优先使用环境变量）
get_odpscmd_base_dir() {
    if [[ -n "$ODPSCMD_BASE_DIR" ]]; then
        echo "$ODPSCMD_BASE_DIR"
    else
        echo "$HOME/.odpscmd"
    fi
}

# 获取配置文件路径
get_config_file() {
    local BASE_DIR=$(get_odpscmd_base_dir)
    CONFIG_FILE="$BASE_DIR/conf/odps_config.ini"
    echo "$CONFIG_FILE"
}

# 检查 NCS 是否已安装
check_ncs() {
    if command -v ncs &> /dev/null; then
        local NCS_PATH
        NCS_PATH=$(which ncs)
        # 跳过 aone-kit 中的 ncs
        if [[ "$NCS_PATH" == *".real/third_party/cli/aone-kit/bin"* ]]; then
            log_error "检测到 aone-kit 中的 NCS，请先运行 install_ncs.sh 安装独立 NCS"
            exit 1
        fi
        return 0
    else
        log_error "未找到 NCS 命令"
        log_info "请先运行 install_ncs.sh 安装 NCS"
        exit 1
    fi
}

# 检查 ODPSCMD 是否已安装
check_odpscmd() {
    local BASE_DIR=$(get_odpscmd_base_dir)
    local CONFIG_FILE="$BASE_DIR/conf/odps_config.ini"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "未找到 ODPSCMD 配置文件: $CONFIG_FILE"
        log_info "请先运行 entry.sh 选择或安装 ODPSCMD"
        exit 1
    fi

    log_success "使用 ODPSCMD: $BASE_DIR"
}



# 配置 endpoint 和 project_name
configure_endpoint_and_project() {
    local EP_LIST="国内(杭州)|http://service-corp.odps.aliyun-inc.com/api,新加坡|http://service-all.ali-sg-lazada.odps.aliyun-inc.com/api,德国|http://service-corp.de-internal.odps.aliyun-inc.com/api,美国蚂蚁|http://service-corp-us.odps.aliyun-inc.com/api,越南蚂蚁|http://service-all.vn-ant.odps.aliyun-inc.com/api,"

    while true; do
        # 选择服务区域
        log_step "STEP 4.2:配置Endpoint"
        if ! select_from_list "$EP_LIST" "服务区域"; then
            return 1
        fi
        END_POINT="$SELECTED_ACCOUNT"

        # 输入项目空间名称
        log_step "STEP 4.3:配置项目空间"
        log_info "请输入项目空间名称:"
        echo "  示例: hero_x_space_dev"
        echo "  [q] 返回选择服务区域"
        read -p "> " PROJECT_NAME

        if [[ "$PROJECT_NAME" == "q" || "$PROJECT_NAME" == "Q" ]]; then
            continue
        fi

        if [[ -z "$PROJECT_NAME" ]]; then
            log_warning "项目空间名称不能为空"
            continue
        fi

        # 校验是否为 dev 空间，不是则自动补 _dev
        if [[ "$PROJECT_NAME" != *_dev ]]; then
            log_warning "${PROJECT_NAME} 不是开发空间，已自动修改为 ${PROJECT_NAME}_dev"
            PROJECT_NAME="${PROJECT_NAME}_dev"
        fi

        log_success "end_point: $END_POINT"
        log_success "project_name: $PROJECT_NAME"
        return 0
    done
}

# 全局变量存储选择结果
SELECTED_ACCOUNT=""

# 获取用户已授权的账号列表
get_authorized_accounts() {
    log_info "正在获取您已授权的账号列表..."

    # 使用 ncs 命令获取账号列表（设置超时防止卡住）
    local NCS_OUTPUT
    NCS_OUTPUT=$(ncs list authorizations odpsuser -o custom-columns=BUC_USER_ID:.extension.bucUserId,BUC_USER_TYPE:.extension.bucUserType,BUC_ACCOUNT_NAME:.extension.bucDomainAccount 2>/dev/null | awk 'NR>2 && NF{print $1, $2, $3}' || true)

    # 清空账号列表
    PRIVATE_COUNT=0
    PRIVATE_ID=""
    PRIVATE_NAME=""
    DEPT_ACCOUNTS=""

    # 解析个人和公共账号
    while IFS=' ' read -r BUC_USER_ID BUC_USER_TYPE BUC_ACCOUNT_NAME; do
        [[ -z "$BUC_USER_ID" ]] && continue
        if [[ "$BUC_USER_TYPE" == "employee" ]]; then
            PRIVATE_COUNT=$((PRIVATE_COUNT + 1))
            PRIVATE_ID="$BUC_USER_ID"
            PRIVATE_NAME="$BUC_ACCOUNT_NAME"
        elif [[ "$BUC_USER_TYPE" == "department" ]]; then
            DEPT_ACCOUNTS="$DEPT_ACCOUNTS$BUC_USER_ID:$BUC_ACCOUNT_NAME,"
        fi
    done <<< "$NCS_OUTPUT"

    # 获取应用账号
    APP_ACCOUNTS=""
    local APP_OUTPUT
    APP_OUTPUT=$(ncs list authorizations odpsaccount --scenario app -o custom-columns=accountName:.extension.accountName 2>/dev/null | awk 'NR>2 && NF{print $1}' || true)
    while IFS=' ' read -r APP_NAME; do
        [[ -z "$APP_NAME" ]] && continue
        APP_ACCOUNTS="$APP_ACCOUNTS$APP_NAME,"
    done <<< "$APP_OUTPUT"

    log_success "账号列表获取完成"
}

# 分页显示账号列表并选择
select_from_list() {
    local LIST="$1"
    local TYPE="$2"
    local PAGE_SIZE=10

    # 检查列表是否为空
    if [[ -z "$LIST" ]]; then
        log_warning "未找到已授权的${TYPE}，请先申请授权"
        return 1
    fi

    # 转换为数组
    local ITEMS=()
    local IFS_OLD="$IFS"
    IFS=','
    for ITEM in $LIST; do
        [[ -n "$ITEM" ]] && ITEMS+=("$ITEM")
    done
    IFS="$IFS_OLD"

    local TOTAL=${#ITEMS[@]}

    if [[ $TOTAL -eq 0 ]]; then
        log_warning "未找到已授权的${TYPE}，请先申请授权"
        return 1
    fi

    if [[ $TOTAL -eq 1 ]]; then
        if [[ "$TYPE" == "服务区域" ]]; then
            local DISPLAY_NAME=$(echo "${ITEMS[0]}" | cut -d'|' -f1)
            log_info "自动选择${TYPE}: $DISPLAY_NAME"
            SELECTED_ACCOUNT=$(echo "${ITEMS[0]}" | cut -d'|' -f2)
        elif [[ "$TYPE" == "公共账号" ]]; then
            log_info "自动选择${TYPE}: ${ITEMS[0]}"
            SELECTED_ACCOUNT=$(echo "${ITEMS[0]}" | cut -d':' -f1)
        else
            log_info "自动选择${TYPE}: ${ITEMS[0]}"
            SELECTED_ACCOUNT="${ITEMS[0]}"
        fi
        return 0
    fi
    # 多选，分页显示
    local PAGE=0
    local MAX_PAGE=$(( (TOTAL + PAGE_SIZE - 1) / PAGE_SIZE - 1 ))

    while true; do
        local START=$((PAGE * PAGE_SIZE))
        local END=$((START + PAGE_SIZE))
        [[ $END -gt $TOTAL ]] && END=$TOTAL

        log_info "请选择${TYPE} (第 $((PAGE + 1))/$((MAX_PAGE + 1)) 页):"
        for ((i=START; i<END; i++)); do
            local IDX=$((i - START))
            local ITEM="${ITEMS[$i]}"
            if [[ "$TYPE" == "公共账号" ]]; then
                local ID=$(echo "$ITEM" | cut -d':' -f1)
                local NAME=$(echo "$ITEM" | cut -d':' -f2)
                echo "  [$IDX] $NAME ($ID)"
            elif [[ "$TYPE" == "服务区域" ]]; then
                local NAME=$(echo "$ITEM" | cut -d'|' -f1)
                echo "  [$IDX] $NAME"
            else
                echo "  [$IDX] $ITEM"
            fi
        done

        echo ""
        if [[ $PAGE -gt 0 ]]; then
            echo "  [p] 上一页"
        fi
        if [[ $PAGE -lt $MAX_PAGE ]]; then
            echo "  [n] 下一页"
        fi
        echo "  [m] 手动输入"
        echo "  [q] 返回上一层"

        echo ""
        read -p "> " CHOICE </dev/tty

        case $CHOICE in
            p|P)
                if [[ $PAGE -gt 0 ]]; then
                    PAGE=$((PAGE - 1))
                fi
                ;;
            n|N)
                if [[ $PAGE -lt $MAX_PAGE ]]; then
                    PAGE=$((PAGE + 1))
                fi
                ;;
            m|M)
                echo "请输入${TYPE} ID/名称:"
                read -p "> " SELECTED_ACCOUNT
                return 0
                ;;
            q|Q)
                return 1
                ;;
            [0-9]*)
                if [[ $CHOICE -ge 0 && $CHOICE -lt $((END - START)) ]]; then
                    local IDX=$((START + CHOICE))
                    local SELECTED="${ITEMS[$IDX]}"
                    if [[ "$TYPE" == "公共账号" ]]; then
                        SELECTED_ACCOUNT=$(echo "$SELECTED" | cut -d':' -f1)
                    elif [[ "$TYPE" == "服务区域" ]]; then
                        SELECTED_ACCOUNT=$(echo "$SELECTED" | cut -d'|' -f2)
                    else
                        SELECTED_ACCOUNT="$SELECTED"
                    fi
                    return 0
                else
                    log_warning "无效的选择"
                fi
                ;;
            *)
                log_warning "无效的输入"
                ;;
        esac
    done
}

# 配置 processCommand
configure_process_command() {
    log_step "STEP 4.1:选择账号"
    log_info "如有疑问请参考：https://aliyuque.antfin.com/zw435783/ugugzt/afm2d3gs3lssgvu7?singleDoc# 中STPE4.Attention 2"

    # 先获取已授权的账号列表
    get_authorized_accounts

    while true; do
        echo "请选择账号类型:"
        echo "1. 个人账号"
        echo "2. 公共账号"
        echo "3. 应用账号"
        echo ""
        read -p "> " ACCOUNT_TYPE

        case $ACCOUNT_TYPE in
            1)
                # 个人账号（只有一个，自动选择）
                log_info "自动选择个人账号: $PRIVATE_NAME ($PRIVATE_ID)"
                log_info "  [Enter] 确认  [q] 返回上一层"
                read -p "> " CONFIRM
                if [[ "$CONFIRM" == "q" || "$CONFIRM" == "Q" ]]; then
                    continue
                fi
                PROCESS_COMMAND="ncs create credential odpsuser --employee-id $PRIVATE_ID -o template -t odpscmd"
                break
                ;;
            2)
                # 公共账号
                if ! select_from_list "$DEPT_ACCOUNTS" "公共账号"; then
                    continue
                fi
                PROCESS_COMMAND="ncs create credential odpsuser --employee-id $SELECTED_ACCOUNT -o template -t odpscmd"
                break
                ;;
            3)
                # 应用账号
                if ! select_from_list "$APP_ACCOUNTS" "应用账号"; then
                    continue
                fi
                PROCESS_COMMAND="ncs create credential odpsaccount --account-name $SELECTED_ACCOUNT -o template -t odpscmd"
                break
                ;;
            *)
                log_warning "无效的账号类型，请重新选择"
                ;;
        esac
    done

    log_success "processCommand: $PROCESS_COMMAND"
}

# 生成配置文件
generate_config() {
    CONFIG_FILE=$(get_config_file)

    log_info "生成配置文件..."

    cat > "$CONFIG_FILE" << EOF
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

    log_success "配置文件已生成: $CONFIG_FILE"
}

# 主函数
main() {
    # 首先检查 /usr/sbin 在 PATH 中
    ensure_usr_sbin_in_path

    echo "========================================"
    echo "    STEP 4/4: ODPSCMD 配置更新 START"
    echo "========================================"
    echo ""

    # 检查 NCS
    check_ncs

    # 检查 ODPSCMD
    check_odpscmd

    # 交互式配置（支持返回上一层）
    while true; do
        configure_process_command
        echo ""

        if configure_endpoint_and_project; then
            break
        fi
        echo ""
        log_info "返回重新配置账号..."
    done
    echo ""

    # 生成配置
    generate_config
    echo ""

    
    echo "========================================"
    echo "    STEP 4/4: ODPSCMD 配置更新 END"
    echo "========================================"
}

main "$@"
