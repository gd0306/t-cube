# 发布与交付检查

源码推送、本机安装、公开发布是三个独立步骤。维护者要求交付公开版本时，必须完成以下检查后再报告完成；未完成的步骤应明确标为未交付，不能用“已更新版本”代替。

1. 锁定打包的完整提交 SHA。同步 macOS 版本／build、Windows package／lockfile 版本，确认工作区未混入私人配置或测试数据。
2. 运行适用回归，保留失败和验证边界。macOS 正式构建、生成及挂载验证 DMG；Windows 使用 `package-windows.yml` 的完整 `ref`，验证实际安装后的应用，不能用源码运行烟测替代。
3. 正常退出本机旧版，备份旧应用及用户 JSON／偏好，安装待发布的正式构建并核对签名、版本、可执行文件 SHA-256 和配置保留情况。系统登记与人工桌面验收分别记录。
4. 暂存并核对两平台文件、`SOURCE_COMMIT.txt` 与 `SHA256SUMS.txt`。准备双语发布说明，说明签名／公证情况和已知限制。
5. 创建指向打包 SHA 的新版本标签与草稿 Release，上传并校验全部附件，再设为最新稳定版。保留旧版本；未经授权不覆盖旧版附件。
6. 用公开未认证下载核对四个附件字节或 SHA-256，核对 GitHub latest、标签提交及包内版本。更新根目录双语下载表、Release 链接、功能可用性说明、Windows README 和本次验收记录后推送。
7. 最后重新核对远端三个 README 链接和公开附件；报告实际可用的下载链接与验证限制。后续仅文档提交可晚于打包 SHA，但必须明确包内应用源码仍对应该打包提交。

常用命令：

```bash
git rev-parse HEAD
bash scripts/build-app.sh
bash scripts/build-dmg.sh --skip-build
bash scripts/verify-dmg.sh
gh workflow run package-windows.yml -f ref=<full-commit-sha>
gh release view --json tagName,isDraft,isPrerelease,assets,targetCommitish
git diff --check
```

没有可用凭据或验证失败时，应说明阻塞事实，保留可审查的安装包和日志，不将未验证的附件作为交付结果。
