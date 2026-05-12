---
name: odps-for-claws
version: 0.31.0
description: 安装和配置 ODPSCMD 离线数据分析环境，执行 SQL 查询、查看表结构、解决权限问题。当用户提到 ODPS、MaxCompute、离线数据分析、odpscmd 或需要执行 SQL 查询时使用。
---

# ODPS 离线数据分析

## 使用 ODPSCMD

### 1. 安装检查

检查 ODPSCMD 是否已安装：

```bash
source ~/.odpscmd_env 2>/dev/null || source ~/.zshrc 2>/dev/null || source ~/.bash_profile 2>/dev/null

if [ -z "$ODPSCMD_BASE_DIR" ] || ! which odpscmd &> /dev/null; then
    echo "ODPSCMD 未安装，需要执行安装流程"
fi
```
若 ODPSCMD 已安装，直接参考「开始使用」章节；未安装则依次执行「开始安装」和「配置 ODPSCMD」章节。

### 2. 开始使用

**STEP 2.1:** 通过如下语句验证安装是否成功；

```bash
odpscmd -e "SELECT 1;" 2>/dev/null || { source ~/.odpscmd_env 2>/dev/null || source ~/.zshrc 2>/dev/null || source ~/.bash_profile 2>/dev/null; odpscmd -e "SELECT 1;"; }
```

**STEP 2.2:** 通过如下语句执行用户SQL，直接使用`odpscmd`即可！不用拼接完整命令！

```bash
odpscmd -e "用户SQL" 2>/dev/null || { source ~/.odpscmd_env 2>/dev/null || source ~/.zshrc 2>/dev/null || source ~/.bash_profile 2>/dev/null; odpscmd -e "用户SQL"; }
```

### 3. 开始安装

若未安装，请严格执行以下步骤完成安装，执行安装脚本时不要指定timeout！！！！！：
**STEP 3.1:** 当不存在Java时自动化为用户安装 Java 运行环境，当无法自动解决时使用如下脚本安装；
```bash
# 使用 chmod，失败时回退到 /bin/chmod
chmod +x ./scripts/install_jre.sh 2>/dev/null || /bin/chmod +x ./scripts/install_jre.sh
./scripts/install_jre.sh
```

**STEP 3.2:** 通过如下命令安装 NCS 工具：
```bash
# 使用 chmod，失败时回退到 /bin/chmod
chmod +x ./scripts/install_ncs.sh 2>/dev/null || /bin/chmod +x ./scripts/install_ncs.sh
./scripts/install_ncs.sh
```

**STEP 3.3:** 通过如下命令安装 ODPSCMD 工具：
```bash
# 使用 chmod，失败时回退到 /bin/chmod
chmod +x ./scripts/install_odpscmd.sh 2>/dev/null || /bin/chmod +x ./scripts/install_odpscmd.sh
./scripts/install_odpscmd.sh
```

### 4. 配置 ODPSCMD

**注意**:

+ 配置文件初始化、重新配置必须严格遵循如下过程；
+ 通过可选框、下拉框或者对话等友好的方式引导用户；
+ 禁止引导用户脱离如下步骤进行配置。

**STEP 4.1:** 生成配置文件

参考如下过程生成 **PROCESS_COMMAND（纯文本字符串，禁止执行）**、**PROJECT_NAME**、**END_POINT** 并替换配置文件 `$ODPSCMD_BASE_DIR/conf/odps_config.ini` 中的对应变量！！！

**绝对禁止（会导致认证失效）：**
- 执行 PROCESS_COMMAND 获取临时凭证
- 将 access_id / access_key / token 等凭证写入配置文件

**正确示例：**
```ini
processCommand=ncs create credential odpsuser --employee-id xxxxxx -o template -t odpscmd
```

**STEP 4.2:** 获取可用账号

查询用户有权限的账号列表：

```bash
# 个人账号和公共账号
ncs list authorizations odpsuser -o custom-columns=BUC_USER_ID:.extension.bucUserId,BUC_USER_TYPE:.extension.bucUserType,BUC_ACCOUNT_NAME:.extension.bucDomainAccount

# 应用账号
ncs list authorizations odpsaccount --scenario app -o custom-columns=accountName:.extension.accountName
```

**STEP 4.3:** 设置账号

展示上一步结果，供用户选择账号，从而生成 PROCESS_COMMAND：

```bash
# 个人/公共账号（使用 BUC_USER_ID）
PROCESS_COMMAND="ncs create credential odpsuser --employee-id $BUC_USER_ID -o template -t odpscmd"

# 应用账号（使用 accountName）
PROCESS_COMMAND="ncs create credential odpsaccount --account-name $accountName -o template -t odpscmd"
```

**STEP 4.4:** 设置项目空间

输入项目空间名称 PROJECT_NAME，自动补全 dev 后缀：

```bash
if [[ ! $PROJECT_NAME == *_dev ]]; then
    PROJECT_NAME="${PROJECT_NAME}_dev"
fi
```

**STEP 4.5:** 选择 END_POINT

| 区域 | END_POINT |
|------|----------|
| 国内(杭州) | http://service-corp.odps.aliyun-inc.com/api |
| 新加坡 | http://service-all.ali-sg-lazada.odps.aliyun-inc.com/api |
| 德国 | http://service-corp.de-internal.odps.aliyun-inc.com/api |
| 美国蚂蚁 | http://service-corp-us.odps.aliyun-inc.com/api |
| 越南蚂蚁 | http://service-all.vn-ant.odps.aliyun-inc.com/api |


---

## 使用技巧

分析数据前，先了解表结构和数据分布：

```sql
-- 查看表结构
desc table_name;

-- 查看最新分区数据样例
select * from table_name where pt=max_pt('table_name') limit 1000;
```

---

## 常见错误

### Access Denied - Authorization Failed

**错误信息**：
```
ODPS-0420095: Access Denied - Authorization Failed
You have NO privilege 'odps:CreateInstance' on {acs:odps:*:projects/xxx}
```

**原因**：在生产空间执行，无创建实例权限。

**解决**：
```bash
./scripts/modify_config.sh
# 将项目空间改为 Dev 空间（脚本自动补全 _dev 后缀）
```

**说明**：Dev 空间可直接访问生产空间的表，无需重新申请权限。

---

#  SKILL简介
## SKILL目录结构

```
odps-for-claws/
├── SKILL.md                    # 本文档
├── scripts/                    # 脚本目录
│   ├── entry.sh                # 统一入口，用户可以手动执行交互式初始化ODPSCMD环境
│   ├── install_jre.sh          # JRE 安装
│   ├── install_ncs.sh          # NCS 认证工具安装
│   ├── install_odpscmd.sh      # ODPSCMD 安装
│   └── modify_config.sh        # 配置管理，用户可以手动执行交互式修改ODPSCMD配置
└── ~/.odpscmd/                 # ODPSCMD 默认安装目录 (用户 HOME 目录下)
    ├── bin/odpscmd
    └── conf/odps_config.ini
```

**默认安装路径：**
- JRE: `~/.jdks/`
- NCS: `~/.ncs/`
- ODPSCMD: `~/.odpscmd/`

**环境变量配置：** 安装脚本会自动将环境变量写入 `~/.zshrc` 或 `~/.bash_profile`（无权限时回退到 `~/.odpscmd_env`）

### 脚本说明

| 脚本 | 用途 | 执行方式 |
|------|------|----------|
| `entry.sh` | 总入口，引导安装/选择 ODPSCMD | `source` 或 `./` |
| `install_jre.sh` | 安装 Java 运行环境 | `source` 或 `./` |
| `install_ncs.sh` | 安装 NCS 认证工具 | `source` 或 `./` |
| `install_odpscmd.sh` | 安装 ODPSCMD | `source` 或 `./` |
| `modify_config.sh` | 配置账号、Endpoint、项目 | `./`（独立执行） |

---

## 环境要求

- **系统**：macOS
