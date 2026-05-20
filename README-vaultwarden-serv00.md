# serve00 搭建 Bitwarden/Vaultwarden 密码保护工具

这是用于 serv00/ct8 FreeBSD 普通用户环境的一键部署脚本。它会手动下载并解包 FreeBSD pkg 包，在用户目录中运行 Vaultwarden，不需要 root，不使用 Docker。

## 使用方式

```sh
fetch -o install-vaultwarden-serv00.sh https://raw.githubusercontent.com/你的用户名/你的仓库/main/install-vaultwarden-serv00.sh
chmod +x install-vaultwarden-serv00.sh
./install-vaultwarden-serv00.sh
```

或者：

```sh
sh install-vaultwarden-serv00.sh
```

## 脚本会询问

- 域名，例如 `p2.442277.xyz`
- 本地端口，例如 `12080`
- 是否允许首次注册
- `ADMIN_TOKEN`，可留空自动生成

## 部署后需要手动完成

### 1. serv00/ct8 面板反代

网站类型选择：

```text
Website type: Proxy
Proxy target: localhost
Proxy port: 12080
Proxy url optional: 留空
Use HTTPS: 不勾
DNS support: 勾选
```

后端必须是：

```text
http://127.0.0.1:12080
```

不要变成：

```text
https://127.0.0.1:12080
```

否则会 502。

### 2. 申请 HTTPS

Vaultwarden 必须 HTTPS 才能正常工作。

一般命令：

```sh
IP=$(dig +short p2.442277.xyz | tail -n 1)
devil ssl www add $IP le le p2.442277.xyz
devil ssl www list
```

### 3. 关闭注册

注册好账号后，编辑：

```sh
ee ~/apps/vaultwarden/.env
```

修改：

```env
SIGNUPS_ALLOWED=false
```

重启：

```sh
cd ~/apps/vaultwarden
./stop.sh
./start.sh
```

## 常用命令

```sh
cd ~/apps/vaultwarden

./start.sh
./stop.sh
./status.sh

tail -f logs/vaultwarden.log
```

## 安全提醒

不要上传这些内容到 GitHub：

```text
.env
data/
logs/
vaultwarden.pid
```

建议 `.gitignore`：

```gitignore
.env
data/
logs/
*.pid
*.pkg
pkg-extract/
```
