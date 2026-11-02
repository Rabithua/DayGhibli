# 0.5.0 验证记录

验证日期：2026-11-02。环境：Apple Silicon，macOS 27。

## 自动测试

35 项测试通过，覆盖按需下载、双屏共享与独立随机、失败保留原状态、自动切换重试、频率日期边界、设置迁移、登录项服务接口、图片清理范围，以及作品页面与显示器的关联、换图/恢复/重启后的同步。

登录项使用替身服务验证。此前已用本机真实计时器验证双屏切换与恢复。

## Sparkle 完整升级

使用包含 Sparkle 的隔离旧测试构建 **0.4.9 / build 9**，升级到 GitHub 上正式发布的 **0.5.0 / build 10**。0.4.9 是版本号降低的测试副本；此前正式的 0.4.x 不包含 Sparkle，需手动安装一次 0.5.0。

通过 Sparkle 官方 `sparkle-cli` 立即触发完整检查，使用正式公开 feed 和下载地址：

- [签名更新列表](https://raw.githubusercontent.com/Rabithua/DayGhibli/main/appcast.xml)
- [0.5.0 正式更新包](https://github.com/Rabithua/DayGhibli/releases/download/v0.5.0/DayGhibli-0.5.0-arm64.zip)

验证结果：

| 检查 | 结果 |
| --- | --- |
| 找到新版并下载 | 完成，1,337,403 字节 |
| 更新签名及解包 | 通过 |
| 实际替换安装 | 版本从 build 9 变为 build 10，日志记录 `Installation Finished.` |
| 自动重启 | 旧进程退出，同一路径启动新进程 |
| 发布包一致性 | 安装后的可执行文件 SHA-256 与线上包一致 |
| Developer ID / 公证 / Gatekeeper | 深层签名、stapler 与 spctl 检查全部通过 |
| 壁纸、应用设置及缓存 | 与测试前一致 |
| 测试结束状态 | 退出测试副本，恢复运行“应用程序”中的正式版 |

本次立即触发检查，覆盖实际下载、验签、安装和重启；未等待每日定时周期。

## 复测注意事项

官方 `sparkle-cli` 是应用包目标。辅助工具应具备完整 `.app` 结构及有效 Info.plist，使用同一 Team 的 Developer ID 签名，并通过 LaunchServices 启动。裸命令行工具在当前执行环境中曾出现 `AuthorizationCreate -60008`；按官方应用包结构、使用 `open -n -W … --args` 启动后，完整升级通过，无须修改系统授权策略。

测试前备份桌面和应用状态，暂停正式实例，再启动隔离旧副本。核对安装日志、磁盘版本、新进程、发布包哈希及签名，最后恢复正式实例。`open -W` 的返回码不能单独作为升级成功的依据。
