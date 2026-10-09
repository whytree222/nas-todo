# 在绿联 DX4600 部署

你已确认 DX4600 可以使用 Docker。本说明使用 Docker Engine 与 Compose 命令；不同 UGOS 版本的图形界面菜单会有差别。若 Docker 页面提供“项目 / Compose”导入功能，可以导入本工程；否则在你自行启用的 SSH 终端执行命令。不要照搬其他型号的 `/volume1` 路径，应在 NAS 文件管理器中确认自己的共享文件夹实际路径。

你的 NAS ZeroTier IP 是 `10.59.218.68`。部署并启动容器后，安卓和 Windows 的服务地址均填写 `http://10.59.218.68:8787`；浏览器健康检查地址是 `http://10.59.218.68:8787/health`。访问令牌使用你部署时生成的 `NAS_TODO_TOKEN`。

本次从这台电脑检查 TCP `10.59.218.68:8787`，收到连接被拒绝（WinError 10061），尚未获得健康检查响应。需要先确认容器运行、端口映射及 NAS 防火墙，不能据此认定 ZeroTier 整个网络不可用。

## 1. 放置工程与数据

在 NAS 的一个共享文件夹内创建 `nas-todo`，把整个工程复制进去。请确认自己所在目录确实是这个工程：

```sh
pwd
ls compose.yaml .env.example server/app.py
docker version
docker compose version
```

以下命令均在这个 `nas-todo` 目录执行。默认数据保存在工程下的 `data/`，Docker 映射为容器内 `/data`，数据库文件为 `data/todo.sqlite`。这个目录必须是 NAS 的持久化共享文件夹，不能只保存在容器可写层中。[Docker 数据卷说明](https://docs.docker.com/engine/storage/bind-mounts/)

后文的宿主机命令按默认 `./data` 编写。若修改了 `NAS_TODO_DATA_DIR`，创建权限、查看备份与恢复时都要把宿主机的 `data/...` 替换为同一个实际目录；容器内 `/data/...` 不变。若系统只有旧版 `docker-compose` 命令，可以使用与本配置兼容的 Compose 版本，但要先确认 `docker compose config --quiet` 的等效检查成功。

创建空目录并赋予容器运行用户 UID/GID `1000:1000` 写权限；需要 NAS 管理权限，某些系统需要在命令前使用 `sudo`：

```sh
mkdir -p data
chown 1000:1000 data
chmod 700 data
```

如果 NAS 对共享文件夹另外设置了 ACL，还需要确保 ACL 允许该运行用户访问。遇到 `permission denied` 时先检查目录所有者与 ACL，不要把整个共享文件夹设为任意用户可写。

## 2. 配置访问令牌

复制 `.env.example` 为 `.env`，编辑：

```dotenv
NAS_TODO_TOKEN=这里替换为自己生成的至少32个字符随机令牌
NAS_TODO_PORT=8787
NAS_TODO_DATA_DIR=./data
```

令牌必须是随机值，不能沿用示例文字或普通密码。可以在 Windows PowerShell 生成一个 32 字节的随机值，再复制到 `.env`；这个步骤无需联网：

```powershell
$tokenBytes = New-Object byte[] 32
$tokenGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$tokenGenerator.GetBytes($tokenBytes)
$tokenGenerator.Dispose()
[Convert]::ToBase64String($tokenBytes)
```

若改用绝对路径，将 `NAS_TODO_DATA_DIR` 改为你刚确认的 NAS 路径，并对那个目录设置权限。服务端会拒绝缺失或过短的令牌。`.env` 只放在自己的 NAS，不进入公开仓库。

## 3. 启动并在局域网验证

```sh
docker compose config --quiet
docker compose up -d --build
docker compose ps
docker compose logs --tail 50 todo-sync
```

首次构建需要访问 Docker 镜像源下载 Python 基础镜像，之后的待办读写只访问你部署的服务。容器内部监听 `8787`；默认 NAS 也映射 `8787`，若端口占用就修改 `.env` 中的 `NAS_TODO_PORT` 并重新启动。`docker compose config --quiet` 只检查配置，不把令牌打印出来。

用同一局域网中的浏览器打开 `http://你的NAS局域网IP:8787/health`。健康检查只证明服务有响应，不证明令牌正确。安卓与 Windows 客户端进入“连接设置”：

- NAS 地址：`http://你的NAS局域网IP:8787`，不追加 `/health` 或其他接口路径。
- 访问令牌：`.env` 中 `NAS_TODO_TOKEN` 的值。

保存后手动同步。安卓创建“手机同步测试”，等它显示同步成功，再让 Windows 同步并确认出现；随后反向测试一次。HTTP 只用于可信局域网或加密 VPN 内部；公网入口使用有效证书的 HTTPS。

## 4. 外网访问

**沿用现有 ZeroTier。** 你已确认 DX4600、安卓和 Windows 都加入同一个网络，下一步只需验证待办端口是否可达。

1. 在现有 ZeroTier 网络的设备列表查找 NAS 的 **Managed IP / ZT IP**；使用这个 IP，不使用网络 ID、设备 Node ID 或家中路由器公网 IP。[ZeroTier 官方连接验证说明](https://docs.zerotier.com/quickstart/)
2. 保持手机和电脑的 ZeroTier 网络已连接，在浏览器打开 `http://10.59.218.68:8787/health`。
3. 健康检查成功后，两端应用的 NAS 地址都填 `http://10.59.218.68:8787`，不追加 `/health`；访问令牌仍是 `.env` 中同一个 `NAS_TODO_TOKEN`。
4. 让手机关闭 Wi-Fi、使用移动网络并保持 ZeroTier 连接，再创建并同步一个测试待办；Windows 也从外部网络验证一次。

可选的 Windows 端口检查，在 PowerShell 中运行：

```powershell
$nasZeroTierIp = '10.59.218.68'
Test-NetConnection -ComputerName $nasZeroTierIp -Port 8787
```

`TcpTestSucceeded: True` 表示 TCP 端口连通，还需 `/health` 与应用同步验证服务和令牌。此方案无需在家中路由器上把待办的 `8787` 端口转发到公网。

如果 ZeroTier 网络显示已连接但 `/health` 仍无法访问，检查 NAS 防火墙是否允许来自现有 ZeroTier 网络的 TCP `8787`、Docker 端口映射与 ZeroTier 网络的访问规则。ZeroTier 虚拟网卡仍受本机防火墙规则约束。[ZeroTier 官方防火墙说明](https://docs.zerotier.com/routertips/)

若 NAS 现有 ZeroTier 运行在网络隔离的 Docker 容器内，需要确认该 Managed IP 能路由到 NAS 宿主机发布的 `8787` 端口；以 `/health` 的实际结果为准，先检查现有网络配置。保持现有的 ZeroTier 部署，不需要为本工程另外安装一个 VPN。

如以后改用其他 VPN，使用其可达的 NAS 地址即可；改为公网域名访问时则需要有效 HTTPS 证书和反向代理。绿联自带远程访问能否转发这个自建 Docker API，取决于实际系统配置。

## 5. 离线与冲突验收

1. 两端先完成一次同步；让安卓断网，新建和编辑待办，关闭再打开应用，确认本机内容仍在。
2. 安卓保持离线，在 Windows 修改同一条待办并同步。
3. 安卓重新联网，打开应用或点击“同步”。新建项目应上传，同条待办的修改应出现冲突选择。
4. 选择要保留的本机或 NAS 版本，等同步完成，两端再次同步后确认结果一致。

应用打开期间会尝试定时同步，回到前台也会尝试。第一版没有系统级后台常驻或推送服务，应用退出时不保证继续同步。

## 6. 备份

服务器运行时使用 SQLite 在线备份，不能仅复制一个正在写入的 SQLite 主文件。下例日期仅是命名示例；每次换一个不存在的新文件名：

```sh
docker compose exec todo-sync python /app/app.py --backup /data/backups/todo-20261008.sqlite
```

成功后文件在 NAS 的 `data/backups/`。命令不会覆盖已存在的备份。保留每日或每周多个版本，并把重要备份额外复制到另一块存储设备；同一 NAS 内备份能恢复误改，不能抵御整个 NAS 损坏。先确认客户端已同步，离线设备上的待上传内容不在 NAS 备份中。

## 7. 从备份恢复

恢复会让服务器回到备份时的内容。操作前暂停两台客户端的同步并保留本机数据，确认备份文件存在，然后在工程目录停止服务：

```sh
docker compose stop todo-sync
pwd
ls data/backups/todo-20261008.sqlite
mkdir data/before-restore-20261008
```

`before-restore-20261008` 必须是一个新的目录名；若已存在，换一个名字。把现有主库以及可能存在的 WAL、SHM 文件一起保留到它里面，避免旧的辅助文件作用于恢复的数据库：

```sh
if [ -f data/todo.sqlite ]; then mv data/todo.sqlite data/before-restore-20261008/; fi
if [ -f data/todo.sqlite-wal ]; then mv data/todo.sqlite-wal data/before-restore-20261008/; fi
if [ -f data/todo.sqlite-shm ]; then mv data/todo.sqlite-shm data/before-restore-20261008/; fi
cp data/backups/todo-20261008.sqlite data/todo.sqlite
chown 1000:1000 data/todo.sqlite
chmod 600 data/todo.sqlite
docker compose start todo-sync
docker compose logs --tail 50 todo-sync
```

对同一数据库实例的旧备份恢复，客户端会重新拉取完整状态，保留本机待上传修改并重新处理冲突。先让一台设备同步并检查结果，再让另一台同步。恢复之前已确认上传、但备份中不存在的内容可能从缓存中移除，原库已保留在 `before-restore-...` 中，可以用它回退。

**不要通过删除 `data/todo.sqlite` 来“重置” NAS。** 新建空主库会产生新的实例标识，客户端会阻止自动把旧缓存合并进去。第一版没有本机导出或重置按钮；遇到“数据库实例不同”时先确认 NAS 地址，必要时恢复原数据库。不要直接清除仍有待上传内容的客户端数据。

## 常见问题

| 现象 | 检查 |
| --- | --- |
| 无法访问 `/health` | 容器状态、端口占用、NAS 防火墙、NAS ZeroTier Managed IP 与 Docker 网络 |
| 返回未授权 | 两端令牌是否与 `.env` 完全一致；改过 `.env` 后重新 `docker compose up -d` |
| 数据目录无法写入 | `data/` 所有者、权限和 NAS ACL；容器运行 UID/GID 为 `1000:1000` |
| 外网失败、内网成功 | 三台设备的现有 ZeroTier 连接状态；网络访问规则；NAS 防火墙对虚拟网卡 TCP `8787` 的规则 |
| 界面显示待上传 | 本机已保存；检查网络、地址、令牌和具体同步错误，再手动同步 |
| 应用退出后不同步 | 第一版在应用运行和回到前台时同步，重新打开应用 |
| 数据库实例不同 | NAS 地址是否指错、主库是否被删除或换成另一套数据；优先恢复原库 |
