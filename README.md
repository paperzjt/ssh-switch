# SSH Switch — GitHub SSH Account Switcher

A local, menu-bar-only macOS app for managing multiple GitHub SSH accounts. It has no main window or Dock icon. Use the vertical-key-and-git menu-bar icon to switch accounts, save the active key pair under a name, or import another key pair.

The app supports English and Simplified Chinese. It follows the macOS preferred language by default; choose **Language → English**, **Language → 简体中文**, or **Language → System Default** in the menu to override it. Your choice is remembered.

When an account is saved or imported, the app authenticates with GitHub using that key via `ssh -T git@github.com`, then stores the GitHub username and the email in the public-key comment in the local profile. Switching uses this saved identity and does not reconnect to GitHub. If no email is present, the current global `user.email` is kept. The local account label is only used for display. Private keys are never uploaded, and GitHub does not provide shell access. If GitHub's SSH host key is not yet trusted, run `ssh -T git@github.com` in Terminal, verify the fingerprint, and retry. Legacy profiles without a verification marker are authenticated once on their first switch.

## Security

- Account keys are stored in `~/.ssh/github-accounts/<account-name>/`; profile directories use mode `0700` and private-key files use mode `0600`.
- Before switching, existing `id_rsa` and `id_rsa.pub` files are backed up to `~/.ssh/github-accounts/.backups/`.
- The app validates key pairs with the system `ssh-keygen`. Encrypted private keys prompt for their passphrase through a macOS dialog; passphrases are not written to disk or passed as command-line arguments.
- Key replacement uses temporary files and rename operations on the same filesystem. If replacing the second file fails, the app attempts to restore the originals.
- The app connects to GitHub only to identify or verify an account. It does not modify Git remotes or SSH configuration.
- Profiles and backups contain ordinary private-key copies. If an imported key is unencrypted, its copies remain unencrypted; security depends on local account permissions and disk protection.

## Build

On macOS 13 or later, run `./build.sh`. The app is built for both Apple Silicon and Intel, and is created at `~/Applications/SSH Switch.app`. Python 3 must be available at `/usr/bin/python3`. Set `SSH_SWITCH_APP_PATH` to choose a different output path. The downloadable app is ad-hoc signed but not notarized; macOS may require you to approve it in Privacy & Security after the first launch attempt.

---

# SSH Switch — GitHub SSH 账号切换器

这是一个仅驻留菜单栏的本地 macOS 应用（没有主窗口或 Dock 图标），用于管理多个 GitHub SSH 账号。点击菜单栏的竖向钥匙与 `git` 字样图标即可切换账号、按名称保存当前密钥对，或导入其他密钥对。

应用支持英文和简体中文。默认跟随 macOS 首选语言；也可以在菜单中选择 **Language → English**、**Language → 简体中文** 或 **Language → 跟随系统**。选择会被记住。

保存或导入账号时，应用会使用对应密钥运行 `ssh -T git@github.com`，识别 GitHub 用户名，并把用户名和公钥注释中的邮箱保存在本地账号档案里。切换时使用已保存的信息，不会重新连接 GitHub。公钥注释没有邮箱时，会保留当前全局 `user.email`。本地账号别名只用于菜单显示。私钥不会上传；GitHub 不提供 shell 访问。如果尚未信任 GitHub 的 SSH 主机密钥，请先在终端运行 `ssh -T git@github.com`、核对指纹后重试。没有验证标记的旧版档案会在首次切换时验证一次。

## 安全说明

- 账号密钥保存在 `~/.ssh/github-accounts/<账号名>/`；档案目录权限为 `0700`，私钥文件权限为 `0600`。
- 切换前会把现有 `id_rsa` 和 `id_rsa.pub` 备份到 `~/.ssh/github-accounts/.backups/`。
- 应用使用系统 `ssh-keygen` 校验密钥对。加密私钥通过 macOS 弹窗输入密码；密码不会写入磁盘或作为命令行参数传递。
- 替换密钥时使用同一文件系统内的临时文件和 rename；如果替换第二个文件失败，会尝试恢复原文件。
- 应用只在识别或验证 GitHub 账号时连接 GitHub，不修改 Git remote 或 SSH config。
- 账号档案和备份均为普通私钥副本。如果原私钥未加密，副本也未加密；安全性依赖本机账户权限和磁盘保护。

## 构建

macOS 13 或更高版本可运行 `./build.sh` 构建。应用同时支持 Apple 芯片和 Intel，默认生成在 `~/Applications/SSH Switch.app`。需要 `/usr/bin/python3`。可通过 `SSH_SWITCH_APP_PATH` 指定其他路径。下载的应用使用 ad-hoc 签名，未经 Apple 公证；首次启动时 macOS 可能要求你在“隐私与安全性”设置中手动允许。
