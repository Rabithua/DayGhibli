# 0.6.0 验证记录

验证日期：2026-11-17。环境：Apple Silicon，macOS 27。

## 构建与签名

- `swift build -c release` 与 `swift test` 全绿，35 项测试 0 失败。
- Developer ID 签名（Team SSK4KVR5FN），内嵌 secure timestamp；`codesign --verify --deep --strict` 通过。
- 公证：asc notarization submit，状态 Accepted（提交 4d5e7c9e）；`stapler staple` 后 `stapler validate` 与 `spctl -a -vv` 均通过（source=Notarized Developer ID）。
- 发布包 `DayGhibli-0.6.0-arm64.zip` 共 1,750,177 字节，SHA-256 `428e150ff70b517c0dcbbb780b1a3d01f5e0eb73439db397d680500321c4ea45`。

## 远端核验

- Release 下载 URL 公开可访问（302 → 200，content-length 1,750,177）；回下载包与本地 SHA-256 一致。
- `sign_update --account me.dayghibli.mac --verify` 校验 enclosure 签名通过。
- appcast.xml 提交推送后，raw feed 与本地字节一致（SHA-256 `6bdb4770…`），0.5.0 条目保留。

## 图标

- 应用图标：撕纸贴纸异形完整入库 icns（10 个表示全部含 alpha，内容 971×1000 居中、四周 ≥12px 透明边距，比例与原图一致无拉伸）。
- 实测发现：macOS 会给传统 icns 自动合成系统玻璃圆角底板（NSWorkspace 渲染验证）；异形图案保留在底板内部，外框形状由系统接管。
- 菜单栏图标：SVG 原生渲染 48×64，眼白挖空为透明，template 模式。实机菜单栏验证：深色壁纸上方自动反白，眼洞清晰。

## 更新实测（0.5.0 → 0.6.0）

- 基线：/Applications 0.5.0（build 10），state.json SHA-256 `a3e8e9ce…`，6 张壁纸。
- 将 `SULastCheckTime` 拨旧后重启应用，Sparkle 自动完成检查、下载、验签、替换安装与重启，全程无人工干预，重启后 15 秒内 build 10 → 11。
- 第一轮检查（15:16:20）未发现新版本：推送 appcast 后撞上 raw.githubusercontent 的 CDN 缓存（TTL 约 5 分钟，取到的还是旧 feed）。复测需等缓存过期，或在发布后等 5 分钟再触发检查。
- 更新后核验：签名与公证票据保留；AppIcon.icns / MenuBarIcon.png 落位 Contents/Resources；state.json 结构完整、6 个壁纸文件全部存在（哈希变化为 lastChanged / nextAutomaticChange 时间戳刷新，应用频率为 hourly 属正常行为）。
