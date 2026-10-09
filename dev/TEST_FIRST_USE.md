# 测试首次使用初始化

`settings.json` 保存 gptr 的默认模型和设置，不保存 Codex 或 Claude Code 的登录凭据。
下面的脚本只移动这一份设置文件，不卸载 R package，也不操作 CLI 的登录状态。

在仓库根目录的终端中先查看目标；不带参数时不会修改文件：

```sh
Rscript --vanilla dev/reset-user-settings.R
```

重置时将原设置移到同目录下的备份文件，并输出恢复命令：

```sh
Rscript --vanilla dev/reset-user-settings.R --apply
```

然后启动一个新的 R session，避免旧进程中的 `gptr.model` 或会话级设置覆盖测试：

```r
devtools::load_all()
peter()
```

预期先出现 Codex CLI、Claude Code CLI、API 配置指引三个选项。选择已安装的 CLI 后，
用户级 `settings.json` 会保存 `model`；再次打开 Peter 时直接显示所选模型，不再初始化。
菜单对齐显示 CLI 是否找到，以及 `Sign In`、`Not Sign In` 或 `Unknown`，不加 `login:` 前缀。
登录检查不发送模型请求，也不保证凭据在线有效；旧版本、不支持检查或检查失败时为
`unknown`，仍可选择。明确未登录时会返回 R 并提示登录，不保存默认模型。
可用 `gptr_providers(check_login = TRUE)` 单独检查。上下文发送授权仍独立确认。
如果插件将 `codex` 或 `claude-cli` 覆盖为非 CLI provider，快捷选项会标为
`not a CLI provider`，选择后返回 R，不保存默认设置。

选择 API 配置或取消会返回 R，不保存默认模型；选择不可用的 CLI 会显示安装及登录指引。
已有默认模型、显式 `model =`、继续已有会话以及 `.stdin = TRUE` 都跳过初始化。

恢复时使用重置脚本输出的完整备份路径：

```sh
Rscript --vanilla dev/reset-user-settings.R --restore "/完整路径/settings.json.setup-backup-..."
```

如果测试期间产生了新的 `settings.json`，恢复命令会先将它备份，再恢复原设置。
