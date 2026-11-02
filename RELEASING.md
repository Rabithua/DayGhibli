# 发布更新

更新源为仓库根目录的 `appcast.xml`，下载包放在 GitHub Releases。应用默认每天检查更新，并通过 Sparkle 自动下载和安装。

[当前正式版](https://github.com/Rabithua/DayGhibli/releases/latest) · [0.5.0 验证记录](docs/verification-0.5.0.md)

1. 修改 `build.sh` 中的版本号和 build number；build number 必须递增。
2. 使用 `SIGNING_IDENTITY='Developer ID Application: …' BUILD_DIR=… APP_OUTPUT=… ./build.sh` 构建。脚本会嵌入 Sparkle、从内到外签名并验证应用。
3. 用 `ditto -c -k --sequesterRsrc --keepParent` 打包应用，执行 `asc notarization submit --file 包路径 --wait`。使用本机已有的 asc 登录配置，不将凭据写入仓库。
4. 公证通过后，对应用执行 `xcrun stapler staple`，再重新打最终 ZIP，文件名如 `DayGhibli-0.5.0-arm64.zip`。此后不要修改或重新打包这份 ZIP。
5. 将最终 ZIP 放入单独的发布目录，用 Sparkle 生成更新列表：

   ```sh
   "$BUILD_DIR/artifacts/sparkle/Sparkle/bin/generate_appcast" \
     --account me.dayghibli.mac \
     --download-url-prefix "https://github.com/Rabithua/DayGhibli/releases/download/v0.5.0/" \
     --maximum-deltas 0 --embed-release-notes \
     --link "https://github.com/Rabithua/DayGhibli" \
     -o appcast.xml 发布目录
   ```

   可在发布目录放同名 `.html` 文件作为更新说明；内容会嵌入并签名。生成工具会签名更新包与 feed，读取应用中的版本、最低 macOS 和架构要求。
6. 提交功能代码并推送 `main`，创建对应 tag 和 GitHub Release，上传这份最终 ZIP。确认下载包可公开访问后，将生成的 `appcast.xml` 原样提交到仓库根目录。
7. 下载远端 ZIP，与本地最终文件比对 SHA-256；用 Sparkle `sign_update --account me.dayghibli.mac --verify` 校验签名。检查 raw feed 与本地字节相同，再验证应用检查更新。
8. 用隔离旧副本实际完成一次下载、安装和重启，核对版本、签名及设置保留情况；完整方法见验证记录。

Ed25519 私钥由 Sparkle `generate_keys --account me.dayghibli.mac` 保存在登录钥匙串中。仓库只包含公钥；不要导出私钥到项目，也不要在新版本中重新生成或替换现有签名密钥。`appcast.xml` 设为 `-text`，避免 Git 换行转换破坏 feed 签名。
