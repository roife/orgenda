# Cloud storage

Orgenda connects one remote workspace at a time and keeps an on-device working copy. Cloud accounts are file-storage connections, not an Orgenda account. Credentials go directly to the selected provider and remain in the iOS Keychain. This implementation has no relay server and no embedded OAuth client secret.

## Provider setup

The checked-in project contains configuration placeholders. A distributor must register its own OAuth applications and supply these **Info.plist string keys** through build settings/configuration. Blank values cause a configuration message before sign-in starts.

| Provider | Client ID key | Redirect URI key | Registration |
| --- | --- | --- | --- |
| OneDrive | `ORGENDAOneDriveClientID` | `ORGENDAOneDriveRedirectURI` | Microsoft Entra public/native client; personal and organizational accounts as required |
| Google Drive | `ORGENDAGoogleDriveClientID` | `ORGENDAGoogleDriveRedirectURI` | Google iOS OAuth client for the exact bundle ID; Drive API enabled |
| Dropbox | `ORGENDADropboxClientID` | `ORGENDADropboxRedirectURI` | Scoped-access application, **App Folder** content access |

Add each redirect URI's scheme to `CFBundleURLTypes` in the application. Register exactly the same redirect URI at the provider. Suggested OneDrive and Dropbox values are `orgenda-onedrive://oauth` and `orgenda-dropbox://oauth`. Google normally uses the reversed iOS client ID, for example `com.googleusercontent.apps.CLIENT:/oauth2redirect`. Use the URI actually registered for the shipping application. No callback web server is needed.

The sign-in flow uses `ASWebAuthenticationSession`, authorization code + SHA-256 PKCE, cryptographically random state/verifier, exact callback validation, and refresh tokens. Tokens are stored as `AfterFirstUnlockThisDeviceOnly` Keychain items, never in `UserDefaults`, connection descriptors, logs, or cloud files. Refresh is single-flight; a request retries authentication once after HTTP 401. Revoked credentials pause synchronization while the local mirror remains readable.

### OneDrive

Request delegated `Files.ReadWrite.AppFolder offline_access`. The initial connection obtains `/me/drive/special/approot` and saves its item ID and drive ID. Microsoft chooses the App Folder name from the registered application; use **Orgenda** as the application name so the visible location is `Apps/Orgenda`. The account identity is the drive ID. Restoring the connection accesses the saved root ID and never resolves `approot` again or recreates a deleted folder.

Microsoft documents App Folder for personal and work/school accounts, while parts of the permissions reference still call the delegated scope preview. Test both account classes before advertising both. Tenant policy may require administrator consent even when the scope itself does not normally require it.

### Google Drive

Request `https://www.googleapis.com/auth/drive`. This is deliberately the full Drive scope: `drive.file` does **not** automatically grant access to files that Emacs, Finder, or another application later creates inside a folder. The application only reads file names/content within the fixed visible `Orgenda` folder. For change detection it reads account-wide change IDs/deletion markers without requesting names/content, then re-enumerates the connected subtree if anything changed.

The OAuth consent screen must accurately disclose the full Drive permission. A public distribution needs the applicable Google OAuth/restricted-scope verification. Do not describe this as a Google-enforced folder-only permission. This implementation does not transmit Drive data to an Orgenda server.

Initial connection finds or creates the single `Orgenda` folder at My Drive's root. Multiple same-named candidate roots are rejected. Its stable file ID is persisted; a subsequently moved folder remains connected, while deletion pauses sync rather than silently making a replacement. Ordinary binary/text files and nested directories are supported. Google-native Docs/Sheets/Slides and shortcuts in the workspace produce an explicit unsupported error instead of being mistaken for downloadable `.org` content.

The adapter uses **Drive REST v2** throughout because it exposes file ETags used by conditional media uploads. It does not combine v2 metadata ETags with undocumented v3 upload behavior.

### Dropbox

Choose **App Folder**, not Full Dropbox, in the Dropbox app console. Enable `files.metadata.read`, `files.content.read`, `files.content.write`, and `account_info.read`. Request offline token access. Use Orgenda as the application name.

The workspace is `Apps/Orgenda/Workspace`. The extra `Workspace` directory supplies a stable folder ID: Dropbox's virtual App Folder root path has no independently persisted root item in this adapter. The first connection may create `Workspace`; restoration and reauthentication only validate the original folder ID. Moving it keeps the connection; deleting it pauses sync. Account identity is Dropbox's `account_id`.

### WebDAV

Enter the HTTPS DAV endpoint, username, password/application password, and a relative workspace directory. For example, a Nextcloud endpoint may already end with `/remote.php/dav/files/USERNAME/`, with `Orgenda` as the directory. The directory is appended to the endpoint; it is not a replacement server-root path. The workspace's parent collection must already exist. Initial setup may create the final workspace collection.

Authentication supports HTTP Basic and Digest challenges through URLSession. System TLS trust is required. There is no insecure HTTP mode, certificate-validation bypass, or password embedded in a URL. Cross-origin redirects and DAV redirects outside the selected root are rejected. GET/HEAD may follow same-origin HTTPS redirects; other methods only follow 307/308 while preserving the method/body. A 303 never replays a PUT. Preauthenticated download URLs used by cloud APIs are requested separately without bearer credentials.

Connecting WebDAV performs more than a successful `PROPFIND`: it creates a randomly named temporary file in the selected directory, checks a strong ETag, verifies `If-None-Match: *`, verifies that stale `If-Match` receives 412 without changing the file, verifies a correct conditional update, and deletes the probe. A server that ignores preconditions is rejected. A failed connection can leave its uniquely named `.orgenda-probe-*` file if the server also refuses cleanup; it never writes to an existing user file.

## Synchronization and safety contracts

`RemoteWorkspaceBackend` operates on validated paths relative to a persisted root. Scans include all ordinary files and directories, including hidden attachment/trash directories and binary metadata; document indexing is a separate responsibility. Enumeration throws if any required page/child fails. It never returns an incomplete list marked as an authoritative full snapshot. HTTP response bodies have byte limits, including responses without `Content-Length`; scans are capped at 50,000 entries.

| Provider | Change detection | Version-bound download | Existing-file save |
| --- | --- | --- | --- |
| WebDAV | Complete `Depth:1` traversal; RFC 6578 is not required | Strong ETag before/after the bounded GET; conditional read | PUT with exact strong `If-Match`; new paths use `If-None-Match: *` |
| OneDrive | Delta where supported; complete traversal fallback; rebuild descendant paths | Metadata ETag before/after preauthenticated content download | Conditional upload-session creation; conflict errors are handled at transfer/commit |
| Google Drive | IDs-only v2 change feed; no changes avoids enumeration; otherwise complete subtree scan | Metadata ETag before/after download plus MD5 when supplied | v2 multipart PUT up to 5 MiB; otherwise resumable PUT with ETag at initiation and 412 handling at commit |
| Dropbox | Recursive list plus cursor; folder moves/deletions rebuild the full tree | Download response carries the exact returned revision | `update(rev)`, `strict_conflict: true`, `autorename: false` |

Google captures the next change cursor **before** scanning, so changes during traversal are examined again on the next sync. Google creation records the operation ID in a private property and uses a pre-generated file ID; retries can identify a previous successful commit. Google permits duplicate sibling names: existing duplicates and new-name collisions surface as conflicts, never arbitrary overwrite selection. Dropbox uploads are currently limited to 150 MiB per file; larger uploads fail explicitly.

`move` never requests replacement of an existing destination. WebDAV uses `Overwrite: F` and source ETag where available; OneDrive requests conflict behavior `fail`; Dropbox disables autorename; Google detects a same-named destination and retains any concurrent duplicate rather than replacing its contents. Stable cloud IDs identify files through moves. WebDAV lacks portable stable IDs, so its ID is the relative path.

HTTP 412 / revision conflicts preserve the queued local edit. The session downloads the other version and requires manual resolution. An upload never retries by substituting the latest ETag and overwriting unseen edits. Authentication repair verifies the **same account and saved root**, retains the original connection ID and offline queue, and stores new credentials only after validation. A different account cannot receive the old workspace's pending edits.

Background work is best effort. The app refreshes on foreground/manual sync and queues offline edits. The current transport is a bounded foreground URLSession; it does not promise fixed-interval background synchronization or uninterrupted transfers after suspension. Large transfer failures leave local data and pending operations available for retry.

## Validation

`CloudBackendTests` uses a custom URLProtocol transport. It exercises streaming size limits, PKCE and form encoding, one-time token refresh, credential host restrictions, WebDAV XML/path/precondition behavior, Dropbox pagination and strict revisions, Google multipart/resumable 412 handling and empty listings, and OneDrive delta path reconstruction. These are protocol fixtures, **not claims of live account interoperability**.

Before enabling a provider in a distributed build, configure credentials and run real-account acceptance checks:

1. Connect, quit/relaunch, work offline, reconnect, and revoke/regrant access while retaining the local outbox.
2. Create/edit/rename files from desktop Emacs, including atomic saves that replace the remote file ID. Verify hidden `.attach` assets and binary image previews.
3. Start two clients from the same baseline, edit both, and verify both contents survive with manual conflict resolution.
4. For Google v2, test valid/stale/forged ETags, multipart upload, and especially: A starts a resumable session; B changes the file; A commits and must receive 412 without destroying B. Do not substitute v3 writes if this fails.
5. For OneDrive, validate commit-time races, zero-byte conditional content writes, pagination/delta expiration, quota failures, and both supported account classes. Zero-byte writes use the conditional content endpoint because upload-session byte ranges cannot represent an empty body.
6. Delete or move the selected root externally. Restore must pause for a missing root and must not recreate it or replay edits into another account/folder.
7. Exercise timeout after successful server commit, same-name creation races, 429/quota responses, TLS failures, and WebDAV Basic/Digest with cross-origin redirects.

No live OAuth accounts, client IDs, refresh tokens, or WebDAV server credentials were provided during development. Live-provider checks remain a release requirement; they are not bypassed or reported as passed by the fixture suite.

## Primary references

- [Apple directory access and security-scoped bookmarks](https://developer.apple.com/documentation/uikit/providing-access-to-directories)
- [Microsoft App Folder](https://learn.microsoft.com/en-us/graph/onedrive-sharepoint-appfolder), [Graph upload-session preconditions](https://learn.microsoft.com/en-us/graph/api/driveitem-createuploadsession?view=graph-rest-1.0), [delta](https://learn.microsoft.com/en-us/graph/api/driveitem-delta?view=graph-rest-1.0)
- [Google Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), [v2 File ETag](https://developers.google.com/workspace/drive/api/reference/rest/v2/files), [v2 upload](https://developers.google.com/workspace/drive/api/reference/rest/v2/files/update)
- [Chromium's v2 conditional upload implementation](https://github.com/chromium/chromium/blob/138.0.7204.157/google_apis/drive/drive_api_requests.cc#L755), [resumable commit-conflict test](https://github.com/chromium/chromium/blob/138.0.7204.157/google_apis/drive/drive_api_requests_unittest.cc#L1831)
- [Dropbox OAuth and App Folder](https://docs.dropboxapi.com/dropbox-api/docs/oauth), [revision write modes](https://dropbox.github.io/SwiftyDropbox/api-docs/latest/Classes/Files/WriteMode.html)
- [WebDAV RFC 4918](https://www.rfc-editor.org/info/rfc4918/)
