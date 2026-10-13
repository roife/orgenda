# 存储与同步接入

Orgenda 通过系统「文件」App 选择工作区文件夹，或连接 WebDAV 服务器。在「设置 → 工作区与同步」中选择或更换存储位置。

## 系统「文件」App

使用系统文件夹选择器选择整个工作区目录，例如本机或 iCloud Drive 中的文件夹。工作区会包含 Org 文件、附件以及根目录的 `config.json`。

Orgenda 保存目录的安全作用域书签，并使用系统协调读写访问目录和子目录。重启后从书签恢复访问；目录不可用或授权失效时，需要重新选择文件夹。只打开或导入单个文件不会授予整个工作区的访问权限。

文件先保存到 Orgenda 的本机快照，再写入所选文件夹。iCloud Drive 的上传和下载由系统管理；应用显示的文件夹写入成功不代表内容已经上传到云端。

## WebDAV

填写 HTTPS 服务器地址、工作区目录、用户名和密码。地址不能包含查询字符串；目录填写相对于服务器地址的路径。密码保存在系统钥匙串中。

首次连接可以创建工作区根目录，并使用临时文件验证服务器的条件写入行为。服务器必须支持强 ETag，以及 `If-Match`、`If-None-Match` 条件请求，避免覆盖已被其他设备修改的文件。连接失败时检查地址、凭据和目录权限。

同步会扫描工作区目录并核对文件版本。重新连接现有工作区时保留原服务器、目录和用户名，仅更新密码并重新验证访问；不会自动创建丢失的根目录。

## 离线修改与冲突

已下载的文本可离线打开、编辑和新建，已缓存的图片可离线查看。修改先保存在本机快照和同步队列中，存储位置恢复可用后再同步。移动、删除、恢复和跨文件归档需要存储位置可用，并且待同步修改已处理。

两端发生冲突时保留修改，由用户选择保留两份或使用其中一版。更换或断开存储位置不会自动迁移工作区；待同步修改可先保存到「文件 → orgenda → Unsaved Edits」。

## 验证

自动验证：

```sh
xcodebuild -project Orgenda.xcodeproj -scheme Orgenda \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OrgendaTests/WebDAVBackendTests \
  -only-testing:OrgendaTests/StorageKeychainTests \
  -only-testing:OrgendaTests/WorkspaceSessionTests test CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=''
```

使用专用测试工作区验收实际存储位置：

1. 选择系统文件夹或连接 WebDAV，确认可读取目录及子目录；取消选择时保留原工作区。
2. 在应用中新建和修改 Org 文件，在存储位置核对内容；电脑端新增和修改文件后，应用同步可见。
3. 离线编辑和新建文件，关闭重开后仍能读取本机内容；联网后完成同步。
4. 系统文件夹在应用重启后恢复访问；iCloud Drive 完成系统上传后，另一台设备能读取修改。
5. WebDAV 凭据失效时保留本机修改，更新密码后可继续同步；原工作区根目录丢失时显示错误。
6. 双端修改同一文件时出现冲突选择，保留两份或使用其中一版后结果符合选择。
7. 有待同步修改时更换或断开存储位置，恢复副本可在 Unsaved Edits 中找到。

用户日常数据不用于测试冲突、删除或授权失效。
