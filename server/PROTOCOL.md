# NAS Todo 同步协议 v1 与个人数据扩展 v1

服务是单用户、单数据库服务。安卓和 Windows 客户端使用同一个 NAS 地址及令牌。Python 3.12 标准库实现；任务、删除记录、操作去重结果、数据库身份都保存在 NAS 的 SQLite 文件中。

## HTTP

默认端口 `8787`。

- `GET /health`：无需令牌，只返回 `{"status":"ok"}`，供 Docker 健康检查使用。
- `POST /api/sync`：`Authorization: Bearer <NAS_TODO_TOKEN>`，`Content-Type: application/json`，请求体为 UTF-8 JSON。
- 令牌至少 32 个非空白的可打印 ASCII 字符，建议使用 `secrets.token_urlsafe(32)`。服务没有默认令牌，缺失或过短会拒绝启动。
- 每个请求须提供一个 `Content-Length`；最大 **1 MiB**，不支持分块请求体。每次最多 **100 个操作**。每个响应关闭连接。
- 令牌、任务正文和 URL 不进入访问日志。服务不添加跨域许可；原生客户端无需 CORS。
- 本服务不自行终止 TLS。远程连接应通过 Tailscale/VPN，或经 HTTPS 反向代理。不要将带令牌的明文 HTTP 直接开放到公网。

## 请求

```json
{
  "instance_id": null,
  "cursor": 0,
  "operations": [
    {
      "op_id": "73c4534c-b51a-4500-b0d5-4f4d15d28f0c",
      "task_id": "8d476940-3c5c-4a88-97ae-193c6b39dbfe",
      "base_version": 0,
      "action": "upsert",
      "data": {
        "title": "买牛奶",
        "note": "下班路上",
        "list_name": "收件箱",
        "due_date": "2026-10-08",
        "priority": 1,
        "completed": false
      }
    }
  ]
}
```

对象必须包含上例中相应层级的全部字段，不接受 JSON 重复键或未声明字段。基础任务 data 仍严格保持六字段。新版在确认服务支持个人扩展后，可在请求顶层增加布尔 `defer_repeats`；不带它的旧版请求继续兼容。UUID 需为标准连字符格式；服务器统一转成小写。

| 字段 | 约束 |
| --- | --- |
| `instance_id` | 首次连接可为 `null`；之后使用服务器返回的 UUID |
| `cursor` | 整数，0 至 2^63−1；`instance_id:null` 时只能为 0 |
| `op_id` | 一次编辑的固定 UUID，重试必须保留此 ID 和完整原始操作 |
| `task_id` | 客户端随机生成的 UUID；删除后的 ID 永久保留 |
| `base_version` | 编辑所依据的服务器版本；创建时为 0，现有任务须精确匹配 |
| `action` | `upsert` 或 `delete` |
| `title` | 非空白字符串，1–200 个 Unicode 字符 |
| `note` | 字符串，最多 10,000 个 Unicode 字符 |
| `list_name` | 字符串，最多 60 个 Unicode 字符 |
| `due_date` | `null` 或真实日期的 `YYYY-MM-DD`，不含时间及时区 |
| `priority` | 整数 0、1、2，分别为普通、中、高；不接受布尔或浮点值 |
| `completed` | JSON 布尔值；不接受整数 0/1 |

`delete` 也需要完整合法的 `data`，但服务器会保留任务已有的正文并只设置删除标记。客户端不得用删除操作改写正文。客户端未同步的新任务若直接删除，可直接撤销其本地创建操作，无需发送不存在任务的删除。

## 响应

```json
{
  "instance_id": "6aa4b8d6-5ffb-4d0a-8b12-0b64491dfd04",
  "cursor": 1,
  "changes": [
    {
      "id": "8d476940-3c5c-4a88-97ae-193c6b39dbfe",
      "title": "买牛奶",
      "note": "下班路上",
      "list_name": "收件箱",
      "due_date": "2026-10-08",
      "priority": 1,
      "completed": false,
      "deleted": false,
      "version": 1,
      "updated_at": "2026-10-08T12:00:00.000000Z",
      "change_seq": 1
    }
  ],
  "results": [
    {
      "op_id": "73c4534c-b51a-4500-b0d5-4f4d15d28f0c",
      "status": "applied",
      "task": {"id": "8d476940-3c5c-4a88-97ae-193c6b39dbfe", "title": "买牛奶", "note": "下班路上", "list_name": "收件箱", "due_date": "2026-10-08", "priority": 1, "completed": false, "deleted": false, "version": 1, "updated_at": "2026-10-08T12:00:00.000000Z", "change_seq": 1}
    }
  ]
}
```

- `cursor` 是本次事务结束时的全局序号。仅实际修改任务时增加，冲突和重试不增加。
- `changes` 按 `change_seq` 升序返回请求游标之后变更过的任务的**当前完整版本**，包括删除记录。相同任务在游标之后编辑多次，只返回最新一条。
- `results` 与请求操作一一对应，按相同顺序排列。`applied` 表示编辑已提交；`conflict` 表示服务器拒绝覆盖现有版本。冲突的 `task` 是当时服务器任务，不存在时为 `null`。
- 空 `operations:[]` 用来拉取其他设备的变更。`cursor:0` 拉取当前完整快照。
- 整批结构验证、身份/游标检查、操作 ID 检查、版本判断、任务更新和操作去重结果写入在同一个事务中完成。业务冲突作为普通结果返回，不会阻止同批其他合法操作提交；请求错误会撤销整批。

## 离线编辑与冲突

客户端先将编辑及 outbox 写入本地持久化存储，再发起同步。重试同一操作必须发送相同的 `op_id` 和完全相同的操作内容；在发送后继续编辑，应保存为后续操作，不能修改正在重试的操作。

服务器永久保存首次操作结果。相同 `op_id`、相同有效载荷会返回原始结果，不再次修改任务；同 ID 不同有效载荷返回整批 HTTP 409 `op_id_reused`。保存的原始结果可能比客户端缓存的服务器版本旧。普通增量同步只合并版本不低于已有服务器版本的任务，防止重复结果将缓存退回旧版本；待发送本地编辑需叠加在服务器缓存之上。

两台设备从版本 1 离线编辑同一任务时，先到的操作生成版本 2，后到的操作得到显式 `conflict`。客户端保留双方内容，让用户选择服务器内容或重新以版本 2 提交本地内容，不能无提示覆盖。被删除的任务无法通过 `upsert` 复活，即使提交最新删除版本号也会冲突；恢复内容应使用新任务 ID 创建副本。

## 错误

所有 API 错误格式为：

```json
{"error":"instance_mismatch","message":"Server database identity changed; reconcile before syncing"}
```

| HTTP | `error` | 含义 |
| --- | --- | --- |
| 400 | `invalid_request` / `invalid_json` / `duplicate_operation` | 无效字段、JSON、或同批重复操作 ID；整批未提交 |
| 401 | `unauthorized` | 缺失或错误令牌 |
| 404 / 405 | `not_found` / `method_not_allowed` | 路由或方法错误 |
| 408 | `request_timeout` | 请求正文超时 |
| 409 | `instance_mismatch` | 已连接的数据库身份改变；整批未提交，需用户确认新服务器及处理本地数据 |
| 409 | `future_cursor` | 客户端游标超过服务器游标，常见于恢复旧备份；整批未提交 |
| 409 | `instance_required` | 非零游标却没有数据库身份 |
| 409 | `op_id_reused` | 操作 ID 被用于不同有效载荷；整批未提交 |
| 409 | `capacity_exceeded` | 超过任务或数据容量；整批未提交 |
| 411 / 413 / 415 | `length_required` / `body_too_large` / `unsupported_media_type` | 请求传输格式或大小错误 |
| 503 / 500 | `server_busy` / `database_unavailable` / `internal_error` | 可以保留 outbox 后重试；结果不确定时使用原始操作 ID |

最多 32 个 HTTP 工作线程、同时处理 2 个请求正文及同步响应，以限制完整快照的内存开销。处理槽位等待超过 5 秒返回 `server_busy`。工作线程耗尽时可能直接返回空正文 HTTP 503，客户端同样保留 outbox 后重试。

收到 `future_cursor` 后，在**身份相同**的前提下，用 `cursor:0,operations:[]` 获取完整快照，替换已确认的服务器缓存并保留待发送编辑及冲突记录，然后重新同步。此时须允许快照中的较低版本成为新的服务器基线，且删除旧缓存中快照没有的已确认任务。不能简单重置游标后继续按“较大版本优先”合并。

## 容量及部署

该版本最多保留 10,000 个任务 ID（包括删除记录），任务 data 的 JSON UTF-8 合计最多 16 MiB，以保证完整快照的内存开销可控。去重历史永久保存，会随编辑次数增加占用 NAS 磁盘空间，不应擅自清理，否则会破坏丢包重试的幂等保证。此版本面向个人待办使用，不提供附件、多人权限或正文加密。

`compose.yaml` 使用 `todo-sync` 服务、`8787` 端口、`./data` 挂载到容器 `/data`。可在 `.env` 改成 NAS 上实际的 `NAS_TODO_DATA_DIR`。容器以 UID/GID `1000:1000` 运行，数据目录须预先创建并允许该身份写入。容器根文件系统只读，数据库文件及 WAL 仅写入 `/data`。不要把该数据目录加入源代码压缩包或 Git。

## 个人数据扩展 v1

新版 `/api/sync` 响应增加 `personal_sync: 1`。旧客户端可以忽略；新客户端只在确认该能力后调用 `POST /api/personal-sync`，认证、UTF-8、请求大小、并发限制和操作数量限制与原接口相同。旧 NAS 不支持时，新客户端保留个人队列并继续基础六字段同步。

个人接口的请求包含 `instance_id`、独立的 `cursor`、`operations`，可选 `release_tasks`（最多 100 个任务 UUID）。数据库身份必须与原同步接口一致。每个操作包含 `op_id`、`kind`、`id`、`base_version`、`action` 和 `data`。

| kind | id | data |
|---|---|---|
| `task_meta` | 对应任务 UUID | `parent_id`（可空）、`tags`（最多20个，每个1–30字符）、`repeat_rule`（可空） |
| `habit` | 习惯 UUID | `name`、`goal_type`（bool/count）、`goal`、`weekdays`（1=周一至7=周日） |
| `habit_checkin` | `习惯UUID:YYYY-MM-DD` | `habit_id`、`date`、`value`（绝对值，撤销为0） |

`repeat_rule` 包含 `frequency`（daily/weekly/monthly）、`interval`（1–365）、`weekdays` 和可空 `month_day`。子任务最多五层，不接受循环。删除父任务和月底清理会在同一个数据库事务中提升保留下来的子任务，不级联完成或删除。任务元数据使用独立记录，旧客户端六字段写入不会清空标签、父子关系或重复规则。

响应包含原数据库 `instance_id`、个人 `cursor`、`changes`、`results`、`generated_tasks` 和 `released_tasks`。记录包含 kind/id/data、deleted/version/updated_at/change_seq；操作结果为 applied 或 conflict，并携带对应 record。客户端需完整校验确认后持久化；版本冲突保留两份数据。相同操作ID重试返回原结果，更改同一ID的操作内容会拒绝整个批次。等值的个人数据更新可确认当前版本，避免服务器提升孤立子任务与客户端相同操作产生假冲突。

重复任务由 NAS 权威生成，下一条使用确定 UUID，并记录来源，防止丢失回复、双端完成、撤销或再次完成造成重复。新客户端的基础写入可带 `defer_repeats: true`，在数据库持久保存暂缓生成标记；完成相应个人信息更新后，通过个人接口 `release_tasks` 确认。元数据冲突时不释放，待用户选择后继续。因此修改重复规则或日期与完成状态之间断网、重启或其他设备查询时，不会按旧规则提前生成。生成的任务不推进客户端的基础任务游标，之后常规同步仍能重放这些变更。

本地 tasks.json 同时保存两类出站队列、已尝试操作ID、暂缓确认及冲突。服务端在原 SQLite 文件中增加个人记录、操作历史和重复记录表，不重建原任务表；数据库基础版本仍兼容旧服务。在线备份覆盖所有新表。个人记录上限为50000，个人JSON数据容量沿用配置中的数据容量上限；达到容量时回滚并保留原数据。没有番茄钟集合或接口。

## 在线备份

```sh
docker compose exec todo-sync python /app/app.py --backup /data/backups/todo-20261008.sqlite
```

备份 CLI 不读取 API 令牌，不启动 HTTP 服务，使用 SQLite 在线备份接口及完整性检查，可在正常同步期间执行。目标必须是不存在的新文件；它不会覆盖已有备份。备份含任务、删除记录、操作结果及身份/游标，不含 `.env` 令牌。将备份另存到其他介质才能应对 NAS 硬件损坏。

恢复必须先停服务，将原数据库及 `todo.sqlite-wal` / `todo.sqlite-shm` 留存到另一目录，再把备份复制为 `/data/todo.sqlite` 并保持 UID/GID 1000 可写，最后重启。不能在服务运行时复制数据库主文件，也不能把旧 WAL 文件与恢复后的主文件混用。恢复同一数据库的旧备份通常保留相同 `instance_id`，客户端可能触发 `future_cursor`；全新空数据库生成新身份并触发 `instance_mismatch`。

## 验证

```sh
python -B -m unittest discover -s server/tests -v
```

测试使用临时数据库与本机 HTTP 端口。受限环境可设置 `NAS_TODO_TEST_TMP` 指向允许写入的临时目录；运行 HTTP 测试需要本机回环连接权限。
