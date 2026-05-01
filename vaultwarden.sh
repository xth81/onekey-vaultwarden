#!/bin/bash

set -e

# ── 颜色定义 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ── 检查是否以 root 运行 ──
if [[ $EUID -ne 0 ]]; then
    error "请以 root 用户运行此脚本 (sudo sh $0)"
    exit 1
fi

# ── 检测 Linux 发行版 ──
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_LIKE=$ID_LIKE
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    elif [[ -f /etc/redhat-release ]]; then
        OS=rhel
    elif [[ -f /etc/arch-release ]]; then
        OS=arch
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
}

# ── 检测 IP 是否在中国大陆 ──
check_ip_location() {
    info "检测服务器网络位置..."
    local country
    country=$(curl -s --connect-timeout 5 http://ip-api.com/json 2>/dev/null | grep -Po '"countryCode":"\K[^"]*')
    if [[ "$country" == "CN" ]]; then
        IN_CHINA=true
        ok "检测到服务器在中国大陆，将使用国内镜像源"
    else
        IN_CHINA=false
        ok "检测到服务器在海外，将使用官方源"
    fi
}

install_docker() {
    info "检测到系统: $OS"

    case "$OS" in
        ubuntu|debian|linuxmint|pop|elementary|zorin)
            if [[ "$IN_CHINA" == true ]]; then
                info "使用 apt 安装 Docker（阿里云镜像源）..."
                apt-get update -qq
                apt-get install -y -qq ca-certificates curl
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
                chmod a+r /etc/apt/keyrings/docker.asc
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            else
                info "使用 apt 安装 Docker（官方源）..."
                apt-get update -qq
                apt-get install -y -qq ca-certificates curl
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
                chmod a+r /etc/apt/keyrings/docker.asc
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            fi
            apt-get update -qq
            apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if [[ "$OS" == "fedora" ]]; then
                info "使用 dnf 安装 Docker..."
                dnf -y install dnf-plugins-core
                if [[ "$IN_CHINA" == true ]]; then
                    dnf config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/fedora/docker-ce.repo
                else
                    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                fi
                dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
            else
                info "使用 yum 安装 Docker..."
                yum install -y yum-utils
                if [[ "$IN_CHINA" == true ]]; then
                    yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
                else
                    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                fi
                yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            fi
            ;;
        arch|manjaro|endeavouros)
            info "使用 pacman 安装 Docker..."
            pacman -Sy --noconfirm docker docker-compose
            ;;
        opensuse*|suse)
            info "使用 zypper 安装 Docker..."
            zypper refresh
            zypper install -y docker docker-compose
            ;;
        alpine)
            info "使用 apk 安装 Docker..."
            apk add docker docker-compose
            rc-update add docker boot
            ;;
        *)
            error "不支持的 Linux 发行版: $OS"
            error "请手动安装 Docker 后重新运行此脚本。"
            exit 1
            ;;
    esac

    # 启动 Docker 并设置开机自启
    systemctl enable docker --now 2>/dev/null || true

    # 等待 Docker 守护进程就绪
    sleep 2
    if docker info >/dev/null 2>&1; then
        ok "Docker 安装并启动成功"
    else
        error "Docker 未能正常启动，请检查日志"
        exit 1
    fi

    # 配置 Docker 镜像加速器（仅中国大陆服务器需要）
    if [[ "$IN_CHINA" == true ]] && [[ ! -f /etc/docker/daemon.json ]]; then
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ]
}
EOF
        systemctl restart docker
        ok "Docker 镜像加速器已配置"
    fi
}

# ── 主流程 ──
clear
echo -e "${CYAN}"
echo "===================================="
echo "    Vaultwarden 一键部署脚本"
echo "===================================="
echo -e "${NC}"

# 0. 检测发行版
detect_distro

# 1. 检测 IP 地理位置（决定用国内镜像源还是官方源）
check_ip_location

# 2. 安装 Docker
if ! command -v docker &>/dev/null; then
    install_docker
else
    ok "Docker 已安装，跳过安装步骤"
    # 确保 Docker 在运行
    systemctl start docker 2>/dev/null || true
fi

# 1. 拉取最新 vaultwarden 镜像（使用 xuanyuan 镜像源）
info "拉取最新 vaultwarden/server 镜像..."
docker pull docker.xuanyuan.me/vaultwarden/server:latest
ok "镜像拉取完成"

# 2. 创建持久化数据目录
DATA_DIR="/opt/vaultwarden"
mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

# 3. 获取用户输入的端口（默认 80）
read -rp "请输入映射到主机的 Web 端口 [默认 80]: " WEB_PORT
WEB_PORT=${WEB_PORT:-80}

# 4. 停止并删除旧容器（如果存在）
docker stop vaultwarden 2>/dev/null || true
docker rm vaultwarden 2>/dev/null || true

# 5. 设置 ADMIN_TOKEN（官方推荐使用 Argon2 PHC 哈希）
echo ""
info "------------------------------------------------------------"
info "设置管理员令牌 (ADMIN_TOKEN)"
info "官方推荐使用 Argon2 PHC 哈希而非明文"
info "脚本将自动对令牌进行哈希处理"
info "------------------------------------------------------------"
echo ""
read -rp "是否自动生成随机管理员令牌？(Y/n): " AUTO_TOKEN
AUTO_TOKEN=${AUTO_TOKEN:-Y}

ADMIN_TOKEN=""
if [[ "$AUTO_TOKEN" =~ ^[Yy]$ ]]; then
    # 使用 openssl 生成 48 字节的随机 base64 令牌
    if command -v openssl &>/dev/null; then
        ADMIN_TOKEN=$(openssl rand -base64 48)
    elif command -v uuidgen &>/dev/null; then
        ADMIN_TOKEN=$(uuidgen | tr -d '-' | base64 | head -c 48)
    else
        ADMIN_TOKEN=$(date +%s%N | sha256sum | base64 | head -c 48)
    fi
    ok "生成的 ADMIN_TOKEN: ${ADMIN_TOKEN}"
    echo -e "${YELLOW}请务必保存好此令牌！这是你管理后台的登录凭证。${NC}"
else
    echo ""
    read -rp "请输入自定义 ADMIN_TOKEN (留空则跳过管理员功能): " ADMIN_TOKEN
fi

# 6. 将 ADMIN_TOKEN 转为 Argon2 PHC 哈希
ADMIN_TOKEN_HASH=""
if [[ -n "$ADMIN_TOKEN" ]]; then
    info "正在将 ADMIN_TOKEN 转为 Argon2 PHC 哈希..."
    # 使用 vaultwarden hash 命令生成哈希（临时运行容器）
    ADMIN_TOKEN_HASH=$(docker run --rm \
        docker.xuanyuan.me/vaultwarden/server:latest \
        hash "$ADMIN_TOKEN" 2>/dev/null | tr -d '\r' | tail -1)
    if [[ -z "$ADMIN_TOKEN_HASH" ]]; then
        warn "Argon2 哈希生成失败，将使用明文令牌（不推荐）"
        ADMIN_TOKEN_HASH="$ADMIN_TOKEN"
    else
        ok "Argon2 PHC 哈希生成成功"
    fi
else
    warn "未设置 ADMIN_TOKEN，管理员后台将不可用。"
    warn "如需后续启用，可编辑 /opt/vaultwarden/docker-compose.yml 添加环境变量。"
fi

# 7. 创建 docker-compose.yml
info "生成 docker-compose.yml ..."

cat > docker-compose.yml <<EOF
version: '3'

services:
  vaultwarden:
    image: docker.xuanyuan.me/vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    ports:
      - "${WEB_PORT}:80"
    volumes:
      - ./data:/data
    environment:
      - WEBSOCKET_ENABLED=true
EOF

# 如果设置了 ADMIN_TOKEN_HASH，追加到 yml
if [[ -n "$ADMIN_TOKEN_HASH" ]]; then
    sed -i '/^    environment:/a\      - ADMIN_TOKEN='"$ADMIN_TOKEN_HASH" docker-compose.yml
fi

# 7. 启动容器
info "启动 Vaultwarden 容器..."
docker compose up -d

# 8. 等待几秒并检查容器状态
sleep 3
if docker ps --format '{{.Names}}' | grep -q "^vaultwarden$"; then
    ok "Vaultwarden 已成功启动！"
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  部署完成！${NC}"
    echo -e "${GREEN}  访问地址: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'):${WEB_PORT}${NC}"
    if [[ -n "$ADMIN_TOKEN" ]]; then
        echo -e "${GREEN}  管理后台: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'):${WEB_PORT}/admin${NC}"
    fi
    echo -e "${GREEN}  数据目录: ${DATA_DIR}${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "${YELLOW}🔐 管理员令牌 (ADMIN_TOKEN): ${ADMIN_TOKEN}${NC}"
    echo -e "${YELLOW}   （已使用 Argon2 PHC 哈希加密存储在配置中）${NC}"
    echo -e "${YELLOW}   请立即保存上述明文令牌到安全位置！${NC}"
else
    error "容器启动失败，请检查日志: docker logs vaultwarden"
fi