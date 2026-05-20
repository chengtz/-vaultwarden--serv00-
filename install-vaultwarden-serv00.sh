#!/bin/sh
# serve00 / ct8 Vaultwarden(Bitwarden compatible) installer for FreeBSD user environment
# 用途：在 serv00/ct8 FreeBSD 普通用户环境中部署 Vaultwarden + Web Vault
# 注意：脚本不会把 ADMIN_TOKEN 写到 GitHub；运行时本地生成/输入。
# Tested flow: FreeBSD 14 amd64, manual pkg extract, local proxy port.

set -eu

APP_NAME="vaultwarden"
APP_DIR="$HOME/apps/$APP_NAME"
PKG_DIR="$APP_DIR/pkg-extract"
DATA_DIR="$APP_DIR/data"
LOG_DIR="$APP_DIR/logs"

VW_PKG_DEFAULT="vaultwarden-1.36.0.pkg"
MYSQL_PKG_DEFAULT="mysql84-client-8.4.8.pkg"
WEBVAULT_PKG_DEFAULT="vaultwarden_web-vault-2026.4.1.pkg"

FREEBSD_REPO_BASE="https://pkg.freebsd.org/FreeBSD:14:amd64/latest/All"

say() {
  printf "\n\033[1;32m%s\033[0m\n" "$*"
}

warn() {
  printf "\n\033[1;33m%s\033[0m\n" "$*"
}

err() {
  printf "\n\033[1;31m%s\033[0m\n" "$*" >&2
}

pause_confirm() {
  printf "\n%s [y/N]: " "$1"
  read ans
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "缺少命令：$1"
    exit 1
  fi
}

download_pkg() {
  file="$1"
  url="$FREEBSD_REPO_BASE/$file"
  cd "$APP_DIR"

  if [ -f "$file" ]; then
    say "已存在：$file，跳过下载"
  else
    say "下载：$file"
    fetch "$url"
  fi
}

make_admin_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48
  else
    date | sha256
  fi
}

check_basic_env() {
  say "检查环境"

  need_cmd uname
  need_cmd fetch
  need_cmd tar
  need_cmd sed
  need_cmd grep

  OS="$(uname -s)"
  ARCH="$(uname -m)"

  echo "OS: $OS"
  echo "ARCH: $ARCH"
  echo "HOME: $HOME"

  if [ "$OS" != "FreeBSD" ]; then
    warn "当前系统不是 FreeBSD。本脚本主要用于 serv00/ct8 FreeBSD 环境。"
    pause_confirm "是否继续？" || exit 1
  fi

  if [ "$ARCH" != "amd64" ]; then
    warn "当前架构不是 amd64。当前下载链接是 FreeBSD:14:amd64 包。"
    pause_confirm "是否继续？" || exit 1
  fi
}

collect_inputs() {
  say "请输入部署信息"

  printf "域名，例如 p2.442277.xyz: "
  read DOMAIN
  if [ -z "$DOMAIN" ]; then
    err "域名不能为空"
    exit 1
  fi

  printf "Vaultwarden 本地端口，例如 12080: "
  read PORT
  if [ -z "$PORT" ]; then
    PORT="12080"
  fi

  printf "是否允许首次注册？建议第一次部署填 yes，注册完成后再关闭。 [yes/no] 默认 yes: "
  read SIGNUP_INPUT
  case "$SIGNUP_INPUT" in
    no|NO|n|N) SIGNUPS_ALLOWED="false" ;;
    *) SIGNUPS_ALLOWED="true" ;;
  esac

  printf "ADMIN_TOKEN 留空则自动生成。请输入 ADMIN_TOKEN 或直接回车: "
  read ADMIN_TOKEN
  if [ -z "$ADMIN_TOKEN" ]; then
    ADMIN_TOKEN="$(make_admin_token)"
    say "已自动生成 ADMIN_TOKEN，会写入本机 .env。请不要把 .env 上传 GitHub。"
  fi

  FULL_DOMAIN="https://$DOMAIN"

  cat <<EOF

即将使用以下配置：

  域名：$DOMAIN
  外部访问：$FULL_DOMAIN
  本地监听：127.0.0.1:$PORT
  安装目录：$APP_DIR
  首次注册：$SIGNUPS_ALLOWED

EOF

  pause_confirm "确认继续安装？" || exit 1
}

prepare_dirs() {
  say "创建目录"
  mkdir -p "$APP_DIR" "$PKG_DIR" "$DATA_DIR" "$LOG_DIR"
}

download_packages() {
  say "下载 FreeBSD pkg 包"
  download_pkg "$VW_PKG_DEFAULT"
  download_pkg "$MYSQL_PKG_DEFAULT"
  download_pkg "$WEBVAULT_PKG_DEFAULT"
}

extract_packages() {
  say "解包 pkg 到用户目录"
  cd "$APP_DIR"

  tar -xf "$VW_PKG_DEFAULT" -C "$PKG_DIR"
  tar -xf "$MYSQL_PKG_DEFAULT" -C "$PKG_DIR"
  tar -xf "$WEBVAULT_PKG_DEFAULT" -C "$PKG_DIR"
}

verify_files() {
  say "检查关键文件"

  VW_BIN="$PKG_DIR/usr/local/bin/vaultwarden"
  MYSQL_LIB="$PKG_DIR/usr/local/lib/mysql/libmysqlclient.so.24"
  WEBVAULT_DIR="$PKG_DIR/usr/local/www/vaultwarden/web-vault"

  if [ ! -x "$VW_BIN" ]; then
    err "未找到 Vaultwarden 主程序：$VW_BIN"
    exit 1
  fi

  if [ ! -f "$MYSQL_LIB" ]; then
    err "未找到 MySQL client 依赖库：$MYSQL_LIB"
    exit 1
  fi

  if [ ! -f "$WEBVAULT_DIR/index.html" ]; then
    err "未找到 Web Vault 前端目录：$WEBVAULT_DIR"
    exit 1
  fi

  echo "Vaultwarden: $VW_BIN"
  echo "MySQL lib: $MYSQL_LIB"
  echo "Web Vault: $WEBVAULT_DIR"
}

write_env() {
  say "写入 .env"

  ENV_FILE="$APP_DIR/.env"

  if [ -f "$ENV_FILE" ]; then
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    warn "已备份旧 .env"
  fi

  cat > "$ENV_FILE" <<EOF
ROCKET_ADDRESS=127.0.0.1
ROCKET_PORT=$PORT

DATA_FOLDER=$DATA_DIR
DATABASE_URL=$DATA_DIR/db.sqlite3

WEB_VAULT_FOLDER=$PKG_DIR/usr/local/www/vaultwarden/web-vault

SIGNUPS_ALLOWED=$SIGNUPS_ALLOWED
INVITATIONS_ALLOWED=false
WEBSOCKET_ENABLED=true

ADMIN_TOKEN=$ADMIN_TOKEN
DOMAIN=$FULL_DOMAIN
EOF

  chmod 600 "$ENV_FILE"
  echo ".env 已创建：$ENV_FILE"
}

write_scripts() {
  say "创建 start.sh / stop.sh / status.sh"

  cat > "$APP_DIR/start.sh" <<'EOF'
#!/bin/sh
cd "$HOME/apps/vaultwarden"

export LD_LIBRARY_PATH="$HOME/apps/vaultwarden/pkg-extract/usr/local/lib:$HOME/apps/vaultwarden/pkg-extract/usr/local/lib/mysql:/usr/local/lib:/usr/local/lib/mysql:$LD_LIBRARY_PATH"

set -a
. ./.env
set +a

mkdir -p logs

if [ -f vaultwarden.pid ]; then
  OLD_PID="$(cat vaultwarden.pid 2>/dev/null || true)"
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Vaultwarden already running, PID: $OLD_PID"
    exit 0
  fi
fi

nohup ./pkg-extract/usr/local/bin/vaultwarden > logs/vaultwarden.log 2>&1 &
echo $! > vaultwarden.pid
echo "Vaultwarden started, PID: $(cat vaultwarden.pid)"
EOF

  cat > "$APP_DIR/stop.sh" <<'EOF'
#!/bin/sh
cd "$HOME/apps/vaultwarden"

if [ -f vaultwarden.pid ]; then
  PID="$(cat vaultwarden.pid 2>/dev/null || true)"
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
  fi
  rm -f vaultwarden.pid
  echo "Vaultwarden stopped"
else
  pkill -f "$HOME/apps/vaultwarden/pkg-extract/usr/local/bin/vaultwarden" 2>/dev/null || true
  echo "Vaultwarden process killed by pattern"
fi
EOF

  cat > "$APP_DIR/status.sh" <<'EOF'
#!/bin/sh
cd "$HOME/apps/vaultwarden"

echo "Process:"
ps aux | grep vaultwarden | grep -v grep || true

echo
echo "Local HTTP:"
PORT="$(grep '^ROCKET_PORT=' .env | cut -d= -f2)"
curl -I "http://127.0.0.1:$PORT" 2>/dev/null || true

echo
echo "Recent log:"
tail -n 20 logs/vaultwarden.log 2>/dev/null || true
EOF

  chmod +x "$APP_DIR/start.sh" "$APP_DIR/stop.sh" "$APP_DIR/status.sh"
}

test_binary() {
  say "测试 Vaultwarden 二进制"

  export LD_LIBRARY_PATH="$PKG_DIR/usr/local/lib:$PKG_DIR/usr/local/lib/mysql:/usr/local/lib:/usr/local/lib/mysql:${LD_LIBRARY_PATH:-}"
  export WEB_VAULT_FOLDER="$PKG_DIR/usr/local/www/vaultwarden/web-vault"

  "$PKG_DIR/usr/local/bin/vaultwarden" --version || {
    err "Vaultwarden 运行测试失败。"
    exit 1
  }
}

start_service() {
  say "启动 Vaultwarden"
  "$APP_DIR/start.sh"
  sleep 2
  "$APP_DIR/status.sh" || true
}

show_proxy_guide() {
  say "下一步：配置 serv00/ct8 反代"

  cat <<EOF

如果你还没有把域名改成 Proxy，请在面板里设置：

  Domain: $DOMAIN
  Website type: Proxy
  Proxy target: localhost
  Proxy port: $PORT
  Proxy url optional: 留空
  Use HTTPS: 不勾
  DNS support: 勾选

关键提醒：
  - 后端目标必须是 http://127.0.0.1:$PORT
  - 不要让面板把后端改成 https://127.0.0.1:$PORT
  - 否则会 502 Bad Gateway

如果当前域名已经是 php/static 类型，可以先删除后重建为 proxy：

  devil www del $DOMAIN

然后用面板添加 Proxy，或根据你机器支持的 devil 参数添加。

检查命令：

  devil www list
  curl -I http://127.0.0.1:$PORT
  curl -I http://$DOMAIN

EOF
}

show_ssl_guide() {
  say "下一步：配置 HTTPS"

  cat <<EOF

Vaultwarden 必须使用 HTTPS，HTTP 下浏览器会提示：
  You are not using a secure context...

serv00/ct8 申请 Let's Encrypt 证书的一般命令：

  IP=\$(dig +short $DOMAIN | tail -n 1)
  echo \$IP
  devil ssl www add \$IP le le $DOMAIN
  devil ssl www list
  curl -Ik https://$DOMAIN

如果你使用 Cloudflare：
  1. 申请 serv00 证书前，建议先把 $DOMAIN 设置为灰云 DNS only
  2. 证书正常后，可以再开橙云
  3. Cloudflare SSL/TLS 选择 Full，不要 Flexible
  4. Vaultwarden 域名建议设置 Cache Bypass，并关闭 WAF/Bot/Challenge/Rocket Loader

EOF
}

show_security_notes() {
  say "安全事项"

  cat <<EOF

1. 注册完成后，务必关闭注册：

   编辑：
     ee $APP_DIR/.env

   修改：
     SIGNUPS_ALLOWED=false

   重启：
     cd $APP_DIR
     ./stop.sh
     ./start.sh

2. 不要把 .env 上传到 GitHub：
   .env 里包含 ADMIN_TOKEN。

3. 建议你的 GitHub 仓库只保存这个安装脚本，不保存 data/、logs/、.env。

4. 冷备用节点每天同步数据时，不要同步 .env。
   只同步：
     data/db.sqlite3
     data/attachments/
     data/sends/
     data/rsa_key.pem

5. p1/p2 双节点不要同时写入同一个 SQLite 数据库。
   推荐：
     p1 主用
     p2 冷备用/只读测试
     p1 -> p2 单向同步

6. 管理后台地址：
     https://$DOMAIN/admin

EOF
}

main() {
  cat <<'EOF'
============================================================
 serve00 搭建 Bitwarden/Vaultwarden 密码保护工具
 FreeBSD 普通用户一键部署脚本
============================================================
EOF

  check_basic_env
  collect_inputs
  prepare_dirs
  download_packages
  extract_packages
  verify_files
  test_binary
  write_env
  write_scripts
  start_service
  show_proxy_guide
  show_ssl_guide
  show_security_notes

  say "脚本执行完成"
}

main "$@"
