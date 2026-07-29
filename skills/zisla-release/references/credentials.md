# zisla 发布凭据

## Sparkle EdDSA 密钥

Sparkle 的 `generate_keys` 生成一对 EdDSA 密钥。公钥写入应用的 `SUPublicEDKey`，私钥由 `generate_appcast` 从 macOS 登录钥匙串读取，用于给 appcast 的 enclosure 生成 `sparkle:edSignature`。

这套密钥免费，不是 Apple 证书，也不要求加入 Apple Developer Program。在 Sparkle 官方 Release 的工具目录中仅执行一次：

```zsh
/absolute/path/to/generate_keys --account 'dev.wzz.zisla'
```

它会将私钥写入当前用户登录钥匙串，并打印公钥。把公钥安全地记录到发布机的构建配置中；不要把私钥复制到文件。以后所有 Preview、Release 和 CI 构建都复用同一个账号下的同一密钥。

当前发布机使用：

```text
service: https://sparkle-project.org
account: dev.wzz.zisla
```

公钥可以出现在构建环境变量和已发布应用中；私钥绝不能导出、提交或打印。确认记录存在时使用不打印密码的命令：

```zsh
security find-generic-password -s 'https://sparkle-project.org' -a 'dev.wzz.zisla' >/dev/null
```

Preview 和 Release 必须共用这一密钥对。不同公钥会让一个已安装通道无法验证另一个通道的 appcast，从而破坏跨通道切换。

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

免费 ad-hoc 签名不影响 Sparkle 的 EdDSA appcast 验证，但不提供 Gatekeeper 公证信誉，也不能使用受限的 WeatherKit entitlement。
