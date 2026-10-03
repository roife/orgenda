# 云盘登录配置与验收

直接登录 OneDrive、Google Drive、Dropbox，需要发行者先为 Orgenda 在各平台注册应用。
SDK 不能代替应用注册。普通用户只需登录自己的云盘账号，不需要提供应用 ID。
Orgenda 使用系统授权窗口和 Authorization Code + PKCE，不使用或保存 client secret。

当前仓库不附带已注册的发行者应用 ID。配置和自动化测试通过不代表真实云盘已验收；
必须完成下方的应用注册、账号授权与同步验收后，才能声称云盘登录可用。

## 注册资料

应用名称使用 `Orgenda`；iOS Bundle ID 是 `com.roifewu.Orgenda`，Apple Team ID 是 `9223UXXW46`。
后台账号登录、验证码、组织授权及条款确认由账号所有者完成。不要创建付费资源或填写虚构的隐私政策地址。

| 服务 | 后台与客户端类型 | 需要提供的公开标识 | 回调地址 |
| --- | --- | --- | --- |
| OneDrive | [Microsoft Entra → App registrations](https://entra.microsoft.com/)，原生公共客户端 | Application (client) ID | `orgenda-onedrive://oauth` |
| Google Drive | [Google Auth Platform → Clients](https://console.cloud.google.com/auth/clients)，**iOS** 客户端 | Client ID | 反转 Client ID 后加 `:/oauth2redirect`，由配置脚本生成 |
| Dropbox | [Dropbox App Console](https://www.dropbox.com/developers/apps)，Scoped access、App folder | App key | `orgenda-dropbox://oauth` |

### OneDrive

1. 注册 Orgenda，账号类型选择支持组织目录及个人 Microsoft 账号，与代码的 `common` 端点一致。
2. Authentication 中添加 Mobile and desktop applications 平台和上表自定义回调 URI。
3. 添加 Microsoft Graph **Delegated** 权限：`Files.ReadWrite.AppFolder`、`User.Read`、`offline_access`。
4. 复制 Application (client) ID，不创建 client secret。

工作区使用 Graph 的 `me/drive/special/approot`。组织策略可能要求管理员同意；以实际账号授权结果为准。
参考：[应用注册](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)、
[OneDrive 应用文件夹](https://learn.microsoft.com/en-us/graph/onedrive-sharepoint-appfolder)。

### Google Drive

1. 创建或选择归属自己的 Google Cloud 项目，启用 Google Drive API。
2. 配置 Google Auth Platform 的 Branding、Audience、Data Access；开发测试阶段添加实际测试账号。
3. 创建 **iOS** OAuth 客户端，填入上面的 Bundle ID；不要用 Web application、Desktop app 或 API key。
4. 当前实现请求 `https://www.googleapis.com/auth/drive`，用于读取电脑端放进 `Orgenda` 文件夹的普通文件。
   `drive.file` 只允许访问授权给应用的文件，不能直接替换而保留当前同步行为。公开发行需完成平台要求的验证。
5. 复制 iOS Client ID。脚本生成反向 scheme，并同时用于 URL Types 和回调 URI。

参考：[Google 原生应用 OAuth](https://developers.google.com/identity/protocols/oauth2/native-app)、
[Drive 权限范围](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)。

### Dropbox

1. 创建 Scoped access 应用，选择 **App folder**。应用名称需符合 Dropbox 的唯一性要求。
2. Permissions 中启用 `files.metadata.read`、`files.content.read`、`files.content.write`、`account_info.read` 并提交。
3. OAuth 2 中登记 `orgenda-dropbox://oauth`，确保允许公共客户端使用 PKCE。
4. 复制 App key，不复制 App secret，也不把控制台生成的个人 access token 打包进应用。

工作区位于该应用文件夹内的 `Workspace`。开发模式先用允许的测试账号验证；公开发行按后台要求申请生产访问。
参考：[Dropbox OAuth 与 PKCE](https://docs.dropboxapi.com/dropbox-api/docs/oauth)。

## 写入工程

运行交互式配置，逐项粘贴公开 ID；可以先配置一家，其他项回车跳过：

```sh
python3 Scripts/cloud_oauth.py configure
```

也可传入 `--onedrive`、`--google`、`--dropbox` 参数。再次运行会保留未修改的服务。
值写到被 Git 忽略的 `Configurations/CloudOAuth.local.xcconfig`，不会写入登录令牌或密码。
`Configurations/CloudOAuth.xcconfig` 由 Debug 和 Release 共用，`project.yml` 的 `configFiles` 引用它。
重新运行 `xcodegen generate --spec project.yml` 不会清空本地配置。

配置变更后重新构建并安装应用。构建脚本检查实际展开的 ID、Google scheme 与回调地址。
Debug 缺失配置时给出警告，允许开发本机、iCloud、WebDAV 功能；Release 缺失或格式错误时构建失败。
CI 需生成同一份本地 xcconfig，或显式传入对应 Xcode build settings；Google ID 和 scheme 必须成对传入。
不要通过关闭检查来分发缺失登录配置的版本。

## 验证

自动验证：

```sh
python3 -m unittest discover -s Scripts -p 'test_*.py'
xcodebuild -project Orgenda.xcodeproj -scheme Orgenda \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OrgendaTests/CloudAuthorizationTests \
  -only-testing:OrgendaTests/CloudBackendTests test CODE_SIGNING_ALLOWED=NO
```

每家使用专用测试工作区完成真实验收：

1. 点击服务后显示正确的 Orgenda 授权页；取消不更换工作区。
2. 同意授权后返回应用，显示当前账号，能读取专属目录。
3. 应用新建 `oauth-check.org`，在云盘核对内容；电脑端修改并新增一个 Org 文件，应用同步后可见。
4. 离线修改，联网后同步；关闭重开后仍可读取离线内容。
5. 令牌过期后能刷新；撤销平台授权后提示重新登录，本机修改保留。
6. 重新登录原账号可继续同步，换账号不会绑定原工作区或上传其待同步修改。

用户日常数据不用于测试冲突、删除或授权撤销。
