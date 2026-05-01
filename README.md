Vaultwarden 一键部署脚本

快速、安全地部署 [Vaultwarden](https://github.com/dani-garcia/vaultwarden)（Bitwarden 非官方自托管服务）

功能特性

一键部署 — 自动检测 Linux 发行版并安装 Docker，无需手动配置
智能源选择 — 自动检测服务器 IP 地理位置：
  - 中国大陆服务器 → 使用阿里云镜像源安装 Docker + 配置镜像加速器
  - 海外服务器 → 使用官方源安装
安全增强 — 自动将 `ADMIN_TOKEN` 转为 Argon2 PHC 哈希，避免明文存储
基于 Docker Compose — 生成标准 `docker-compose.yml`，便于维护和升级

使用方式

bash
# 下载脚本
wget https://raw.githubusercontent.com/xth81/onekey-vaultwarden/main/vaultwarden.sh

# 赋予执行权限
chmod +x vaultwarden.sh

# 以 root 运行
sudo bash vaultwarden.sh
