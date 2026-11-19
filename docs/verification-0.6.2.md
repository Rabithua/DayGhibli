# 0.6.2 验证记录

验证日期：2026-11-19。环境：Apple Silicon，macOS 27.2。

## 本版变更

仅更正 `SourceNotice.txt` 的来源标注：明确图片目录实际取数来源为本账号 fork（Rabithua/awesome-ghibli-images，README.zh.md blob SHA `c001be7b…` 钉死），保留原始上游 chius-me 出处。已复核目录 1278 个链接与 fork README.zh.md 逐条一致（双向 0 差异）；上游当日 HEAD 内容有增补，图片链接集与 fork 相同。无功能与数据变化。

## 构建、签名与发布

- `swift test` 全绿（35 项）。Developer ID 签名 + 公证 Accepted（提交 47c5eafd）+ stapler / spctl 通过。
- 发布包 `DayGhibli-0.6.2-arm64.zip` 共 2,501,080 字节，SHA-256 `263f7fdbfe29c4a115b536e3125d63cf46a167a42094554e74ed711162730566`；远端下载包逐字节一致；enclosure ed 签名校验通过；raw feed 与本地一致（SHA-256 `3d235218…`）。
- generate_appcast 本轮移除了 0.5.0 旧条目（feed 现含 0.6.0 / 0.6.1 / 0.6.2）。Sparkle 更新判定对 feed 全部条目比版本，旧版用户升级路径不受影响。

## 更新实测（0.6.1 → 0.6.2）与新发现

- 常规路径本次未自动完成换装：检查、下载、验签、解包入暂存区均正常（暂存 0.6.2/build 13，13:50:09），但退旧换新未在运行会话内触发。
- 新发现行为：**重启应用后，Sparkle 自动续装暂存更新**（15 秒内 build 12 → 13）。即暂存未换装的场景下，用户下次启动即可完成更新，无需手动重装。
- 前一轮的 CDN 缓存问题本次未复现：推送后先以 curl 验证 raw feed（内容新鲜），Sparkle 随后取到同一份新 feed。推断 curl 先行刷新了边缘缓存；发布后立即验证 feed 再触发检查可规避该坑。
- 更新后核验：0.6.2 / build 13，签名与公证票据保留；Assets.car 落位；SourceNotice.txt 为新文案（fork 引用 2 处）；登录项状态仍为 enabled（status: 1，跨两次 Sparkle 更新存活）；state.json 15 键完好。
