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

免费 ad-hoc 签名不提供 Gatekeeper 公证信誉，也不能使用受限的 WeatherKit entitlement。应用内更新流程只下载 DMG，不会替换已安装应用。
