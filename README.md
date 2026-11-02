# 每日吉卜力

原生 macOS 菜单栏壁纸工具。支持 macOS 14 及以上、Apple Silicon。

[下载最新版](https://github.com/Rabithua/DayGhibli/releases/latest) · [发版流程](RELEASING.md) · [验证记录](docs/verification-0.5.0.md)

## 使用

下载 ZIP，解压后将“每日吉卜力.app”放进“应用程序”，双击启动。应用只显示菜单栏图标，没有独立窗口或 Dock 图标。

菜单按以下顺序分组：

| 分组 | 菜单内容 |
| --- | --- |
| 操作 | 换一张、影片、恢复上次壁纸；失败时可查看错误 |
| 壁纸信息 | 当前作品名称；多屏显示各自屏幕名称；点击打开对应的吉卜力官方作品页面 |
| 设置 | 各显示器独立随机、自动切换、切换频率、登录时启动、检查更新 |

“退出”位于菜单底部，快捷键为 ⌘Q。菜单栏图标使用 `photo.on.rectangle.angled`。

## 壁纸切换

只在手动或定时切换时下载所需图片；打开菜单、选择影片、修改设置都不会预先下载。全部图片下载和验证成功后再设置桌面。

- **各显示器独立随机**：开启后每块屏幕使用不同的随机图片，下一次切换时生效；关闭时共享一张图片。
- **自动切换**：首次默认关闭。休眠错过任务后在唤醒时补换；失败后 15 分钟重试。工具需保持运行。
- **登录时启动**：使用 macOS 系统登录项；需要系统批准时提供设置入口。

| 频率 | 切换时间 |
| --- | --- |
| 每小时 | 开启或上次成功切换后 1 小时 |
| 每 6 小时 | 开启或上次成功切换后 6 小时 |
| 每天（默认） | 当地时间 09:00 |
| 每周 | 当地时间周一 09:00 |

手动成功换图或修改频率后会重排下一次任务。多虚拟桌面的行为由 macOS 控制，当前版本不承诺同步所有 Space。

## 来源与存储

图库包含 26 部作品、1278 个图片链接，整理自 [awesome-ghibli-images](https://github.com/chius-me/awesome-ghibli-images)。图片按需从吉卜力官网下载，保留原始文件和分辨率，桌面显示由 macOS 缩放。[图片来源与权利说明](Resources/SourceNotice.txt)。

设置和缓存位于 `~/Library/Application Support/DayGhibli/`。每块已记录的显示器只保留当前和上一张图片，共用图片只存一份，暂未连接的显示器记录也会保留。启动、成功换图及恢复后自动清理；下载、设置或保存失败时跳过清理。清理仅处理工具自己的缓存文件。

## 应用更新

0.5.0 起接入 Sparkle，默认每天检查并自动下载更新；后台更新通常在应用退出时安装。“设置 → 检查更新…”可手动检查并安装重启。0.4.x 用户需要先手动安装一次 0.5.0。

正式包使用 Developer ID 签名和 Apple 公证，Sparkle 同时验证更新列表及更新包的 Ed25519 签名。

## 开发

需要 Xcode 或包含 macOS SDK 的 Swift 6 工具链。

```sh
swift test
./build.sh
```

`build.sh` 默认为当前架构构建并使用 ad-hoc 签名供本地开发。可用 `BUILD_DIR`、`APP_OUTPUT` 指定路径，使用 `SIGNING_IDENTITY` 指定正式签名证书。

依赖 Sparkle 2.10.1，由 Swift Package Manager 锁定版本；许可见 [Sparkle-LICENSE.txt](Resources/Sparkle-LICENSE.txt)。签名私钥保存在本机钥匙串。

35 项自动测试通过，完整升级链路已实测。[验证范围与结果](docs/verification-0.5.0.md)。

## 卸载

退出后删除应用。若需一并移除图片和设置，可删除 `~/Library/Application Support/DayGhibli/`。
