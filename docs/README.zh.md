# Claude Code HUD

在 Claude Code 状态栏实时显示使用量信息的自定义 HUD。

[English](../README.md) | [한국어](README.ko.md) | [日本語](README.ja.md)

## 预览

```
Opus 4.6 | 13m 28s (api:8m 41s) | $2.07 | d:$2.07 m:$2.07 | in:88.9K out:26.7K
ctx  [█████░░░░░░░░░░░░░░░] 29%
5h   [░░░░░░░░░░░░░░░░░░░░]  4%  reset 3h 30m
week [████░░░░░░░░░░░░░░░░] 22%  reset 4d 19h
```

| 行 | 内容 |
|----|------|
| 1 | 模型名、会话时间（API 时间）、会话费用、日/月累计费用、输入输出 token |
| 2 | 上下文窗口使用率进度条 |
| 3 | 5 小时计划额度使用率 + 重置倒计时 |
| 4 | 周计划额度使用率 + 重置倒计时 |

进度条颜色：绿色(<50%) → 黄色(50-79%) → 红色(80%+)

## 安装

```bash
git clone https://github.com/kangnam7654/claude-code-hud.git
cd claude-code-hud
./install.sh
```

自动创建符号链接并配置 `~/.claude/settings.json`。安装后请重启 Claude Code。

卸载：

```bash
./install.sh --uninstall
```

## 工作原理

### 状态栏 (`statusline.sh`)

读取 Claude Code 通过 stdin 发送的会话 JSON，显示：
- 会话指标（费用、时间、token）
- 上下文窗口使用率进度条
- 计划使用率进度条 + 重置倒计时（基于缓存的 API 数据）
- 日/月累计费用（基于会话日志）

### 计划用量 (`fetch-plan-usage.sh`)

- 使用 `~/.claude/.credentials.json` 的 OAuth token 调用 `api.anthropic.com/api/oauth/usage`
- 30 秒缓存 (`/tmp/claude-plan-usage.json`)，不影响状态栏速度
- 缓存过期时在后台自动刷新

### 会话日志 (`log-session.sh`)

- SessionEnd 钩子在会话结束时将费用/token 记录到 `~/.claude/usage-log.jsonl`
- 状态栏将当前会话费用 + 历史会话费用汇总显示

## 文件结构

```
install.sh             # 安装/卸载脚本
statusline.sh          # HUD 主脚本（在状态栏中运行）
fetch-plan-usage.sh    # Anthropic OAuth API 计划用量查询 + 缓存
log-session.sh         # SessionEnd 钩子 - 将会话指标记录为 JSONL
```

## 要求

- Claude Code（Max 计划）
- `jq`、`curl`、`bc`
