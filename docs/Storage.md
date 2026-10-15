# 存储与同步接入

Orgenda 通过系统「文件」App 选择工作区文件夹，或连接 WebDAV 服务器。在「设置 → 工作区与同步」中选择或更换存储位置。

## 系统「文件」App

使用系统文件夹选择器选择整个工作区目录，例如本机或 iCloud Drive 中的文件夹。工作区会包含 Org 文件、附件以及根目录的 `config.json`。

Orgenda 保存目录的安全作用域书签，并使用系统协调读写访问目录和子目录。重启后从书签恢复访问；目录不可用或授权失效时，需要重新选择文件夹。只打开或导入单个文件不会授予整个工作区的访问权限。

文件先通过 SQLite 事务保存到 Orgenda 的本机状态库和不可变 blob，再写入所选文件夹。iCloud Drive 的上传和下载由系统管理；应用显示的文件夹写入成功不代表内容已经上传到云端。

## WebDAV

填写 HTTPS 服务器地址、工作区目录、用户名和密码。地址不能包含查询字符串；目录填写相对于服务器地址的路径。密码保存在系统钥匙串中。

首次连接可以创建工作区根目录，并使用临时文件验证新建文件不覆盖、更新后旧版本写入被拒绝。标准 WebDAV 服务器需要提供强 ETag，并执行 `If-Match`、`If-None-Match` 条件请求；ETag 可从文件属性或 HTTP 响应头读取。

坚果云使用 `https://dav.jianguoyun.com/dav/`、账号邮箱和第三方应用密码，目录可填写 `/Orgenda`。应用原样使用其未加引号的版本标识；新文件通过同目录临时上传及 `MOVE`（`Overwrite: F`）避免同名覆盖。任何写入保护检查失败均不接受连接。

编辑后的自动同步只推送待上传修改；进入前台、定时、手动同步及条件写入失败时扫描工作区并核对版本。PUT 返回强 ETag 时直接确认，其余情况读回验证；WebDAV 请求最多并发 4 个。重新连接现有工作区时保留原服务器、目录和用户名，仅更新密码并重新验证访问；不会自动创建丢失的根目录。

## 离线修改与冲突

已下载的文本可离线打开、编辑和新建，已缓存的图片可离线查看。修改先保存在本机快照和同步队列中，存储位置恢复可用后再同步。移动、删除和恢复也会先在本机入队，存储位置恢复可用后按顺序回放。尚未缓存正文的恢复请求可离线入队，正文在连接恢复后读取。跨文件归档一次提交两份本机草稿，目标文件确认成功后才上传源文件；中断或目标变化时保留可恢复的内容副本。

两端互不重叠的文本修改自动合并，重叠修改保留为冲突，由用户选择保留两份或使用其中一版。目录操作遇到目标重名时保留已有目录，确认后可换一个目标重试。更换或断开存储位置不会自动迁移工作区；待同步修改可先保存到「文件 → orgenda → Unsaved Edits」。

## 验证

自动验证：

```sh
xcodebuild -project Orgenda.xcodeproj -scheme Orgenda \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OrgendaTests/WebDAVBackendTests \
  -only-testing:OrgendaTests/StorageKeychainTests \
  -only-testing:OrgendaTests/WorkspaceSessionTests \
  -only-testing:OrgendaTests/WorkspaceStorageBenchmarkTests \
  -only-testing:OrgendaTests/WorkspaceStorageConcurrencyTests test CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=''
```

使用专用测试工作区验收实际存储位置：

1. 选择系统文件夹或连接 WebDAV，确认可读取目录及子目录；取消选择时保留原工作区。
2. 在应用中新建和修改 Org 文件，在存储位置核对内容；电脑端新增和修改文件后，应用同步可见。
3. 离线编辑、新建、移动、删除和恢复文件，关闭重开后保留内容及操作顺序；联网后完成同步。跨文件归档中断时核对源、目标均没有丢失正文。
4. 系统文件夹在应用重启后恢复访问；iCloud Drive 完成系统上传后，另一台设备能读取修改。
5. WebDAV 凭据失效时保留本机修改，更新密码后可继续同步；原工作区根目录丢失时显示错误。
6. 双端修改同一文件时出现冲突选择，保留两份或使用其中一版后结果符合选择。
7. 有待同步修改时更换或断开存储位置，恢复副本可在 Unsaved Edits 中找到。

用户日常数据不用于测试冲突、删除或授权失效。

基准使用内存 WebDAV 服务器、1000 个文件、10,240,000 字节；包含本机提交、两次界面增量读取与一次推送，不含首次导入、网络延迟和解析。结果保存在 [StorageBenchmark.json](StorageBenchmark.json)，耗时只用于本机对照，请求数与 blob 读取量由测试断言约束。状态写入字节数统计编码后的行负载，WAL 文件增长另列；均不是存储设备的物理写入量。坚果云等需要额外 HEAD 获取版本的服务，请求数可能高于通用回退样本。

新状态库直接使用 `state.sqlite`，不读取或迁移旧 `manifest.json`，旧缓存文件保留。完整状态模型见 [架构说明](Architecture.md)。
