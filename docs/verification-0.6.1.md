# 0.6.1 验证记录

验证日期：2026-11-17。环境：Apple Silicon，macOS 27.2。

## 登录项修复（根因与证据链）

现象：点击菜单「登录时启动」无反应、无对勾。该问题自 0.5.0 起存在。

1. 点击时日志：`ServiceManagement Service status: 3`（即 `.notFound`）。
2. 探针实证（一次性 Developer ID 签名应用，本机）：
   - 从未注册的应用初始 `SMAppService.mainApp.status` 为 **3（.notFound）**，而非 0（.notRegistered）
   - 从 .notFound 直接 `register()` **成功**，注册后 status 变 1（enabled）；unregister 后回到 0
3. 根因：`LoginItemController.setEnabled` 把 `.notFound` 当错误抛出（`serviceNotFound`），注册从未被尝试；错误仅在菜单中以不显眼的「查看错误…」按钮呈现。
4. 修复：`.notFound` 并入注册分支，与 `.notRegistered` 同样尝试 `register()`；仅 register() 本身抛错才向外透出。`isEnabled`（.notFound 仍为 false）、`needsApproval`、unregister 分支不变。

## 构建、签名与发布

- `swift build -c release` 与 `swift test` 全绿，35 项测试 0 失败。
- Developer ID 签名 + 公证 Accepted（提交 09310e16）+ stapler validate / spctl 通过。
- 发布包 `DayGhibli-0.6.1-arm64.zip` 共 2,500,991 字节，SHA-256 `e8fca6b70a0433ce4ebe36919498d5636723ef08e5441ea4aff1822bdb20645a`；远端下载包与本地逐字节一致；`sign_update --account me.dayghibli.mac --verify` 通过；raw feed 与本地一致（SHA-256 `3714f2e6…`）。

## 图标

- 新增 `Resources/AppIcon.icon`（分层格式）：全出血单层，无 shadow、无 translucency，`fill` 与源图黑底同色。
- `build.sh` 构建期以 actool 编译（`--platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon`），产出 Assets.car（1,147,256 字节）+ AppIcon.icns fallback（50,778 字节）；Info.plist 同时声明 CFBundleIconFile 与 CFBundleIconName。
- 实测渲染（NSWorkspace on 发布 bundle）：macOS 27 下按原图渲染，系统仅施加圆角，**无玻璃底板、无内缩**。旧系统（<26）回退 icns。
- 应用图标源图更新为 Frame 13（1024×1024 全不透明黑底撕纸贴纸）。

## 更新实测（0.6.0 → 0.6.1）

- /Applications 0.6.0（build 11）经 Sparkle 自动更新到 0.6.1（build 12），重启后 15 秒内完成，全程无人工干预。
- 更新后核验：签名与公证票据保留；Assets.car / AppIcon.icns / MenuBarIcon.png 落位；state.json 结构完整（15 键）、6 个壁纸文件全部存在。
- 再次确认 CDN 坑（与 0.6.0 时一致）：推送 appcast 后立即触发的检查会命中 raw.githubusercontent 边缘缓存拿到旧 feed；等约 5 分钟 TTL 过期后重试即成功。后续发布后应至少等 5 分钟再触发更新验证。
