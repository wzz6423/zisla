# zisla 发布凭据

## GitHub

使用 `gh auth login` 登录。令牌保存在 GitHub CLI 的凭据存储中，至少需要仓库和 Release 写权限。只用 `gh auth status` 检查状态，不要输出令牌。

## Gitee

在 Gitee 的个人设置中创建具有仓库读写权限的私人令牌。使用 macOS Keychain 保存 API 令牌；API 不会从 git credential helper 自动取得令牌。

```zsh
read -rs GITEE_RELEASE_TOKEN
printf '\n'
security add-generic-password -U \
  -a 'wzz6423' \
  -s 'gitee.com.zisla.release-token' \
  -w "$GITEE_RELEASE_TOKEN"
unset GITEE_RELEASE_TOKEN
```

Gitee Release API 的 PATCH 必须提交 `tag_name`。附件是独立对象，不能通过 GitHub 镜像自动同步。

## 代码签名

| 分发方式 | `CODE_SIGN_IDENTITY` | 成本 | 用户体验 |
| --- | --- | --- | --- |
| 免费 Preview | `-` | 免费 | ad-hoc，未公证，用户可能需要选择“仍要打开” |
| Developer ID | `Developer ID Application: ...` | Apple Developer Program | 可公证、可 stapling、普通用户安装更顺畅 |

免费 ad-hoc 签名不提供 Gatekeeper 公证信誉，也不能使用受限的 WeatherKit entitlement。首次安装可能需要用户选择“仍要打开”，但已安装的 Sparkle 版应用会验证 EdDSA 签名后自动替换与重启。

## Sparkle EdDSA 私钥

- 公钥内置在应用 `Info.plist` 的 `SUPublicEDKey`；它不包含 Apple Developer 或个人身份信息，可公开发布。
- 私钥账户为登录钥匙串中的 `zisla-update-ed25519`。非交互发布优先使用 `SPARKLE_ED_KEY_FILE` 指向单独保管的私钥文件；文件权限设为 `600`。
- 不要将私钥放进仓库、Release 附件、appcast、日志、命令行参数或 CI 输出。`generate_appcast` 只接收私钥文件路径，不应输出其内容。
- 当前 appcast URL 会公开 GitHub 与 Gitee 仓库地址 `wzz6423/zisla`。若不希望公开该用户名，先迁移到组织账号或独立更新域名，再同步修改 Gitee 主 feed、GitHub fallback feed 及其发布脚本前缀。
