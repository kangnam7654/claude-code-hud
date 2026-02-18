# Claude Code HUD

Claude Codeのステータスラインに使用量情報をリアルタイム表示するカスタムHUD。

[English](../README.md) | [한국어](README.ko.md) | [中文](README.zh.md)

## プレビュー

```
Opus 4.6 | 13m 28s (api:8m 41s) | $2.07 | d:$2.07 m:$2.07 | in:88.9K out:26.7K
ctx  [█████░░░░░░░░░░░░░░░] 29%
5h   [░░░░░░░░░░░░░░░░░░░░]  4%  reset 3h 30m
week [████░░░░░░░░░░░░░░░░] 22%  reset 4d 19h
```

| 行 | 内容 |
|----|------|
| 1 | モデル名、セッション時間(API時間)、セッションコスト、日次/月次累計コスト、入出力トークン |
| 2 | コンテキストウィンドウ使用率バー |
| 3 | 5時間プラン上限使用率 + リセットタイマー |
| 4 | 週間プラン上限使用率 + リセットタイマー |

バーの色: 緑(<50%) → 黄(50-79%) → 赤(80%+)

## インストール

```bash
git clone https://github.com/kangnam7654/claude-code-hud.git
cd claude-code-hud
./install.sh
```

シンボリックリンクの作成と `~/.claude/settings.json` の設定を自動で行います。インストール後、Claude Codeを再起動してください。

アンインストール:

```bash
./install.sh --uninstall
```

## 仕組み

### ステータスライン (`statusline.sh`)

Claude Codeがstdinで送信するセッションJSONを読み取り、以下を表示:
- セッション指標（コスト、時間、トークン）
- コンテキストウィンドウ使用率バー
- プラン使用率バー + リセットタイマー（キャッシュされたAPIデータ）
- 日次/月次累計コスト（セッションログベース）

### プラン使用量 (`fetch-plan-usage.sh`)

- `~/.claude/.credentials.json` のOAuthトークンで `api.anthropic.com/api/oauth/usage` を呼び出し
- 30秒キャッシュ (`/tmp/claude-plan-usage.json`) でステータスラインの速度に影響なし
- キャッシュが古くなるとバックグラウンドで自動更新

### セッションログ (`log-session.sh`)

- SessionEndフックでセッション終了時にコスト/トークンを `~/.claude/usage-log.jsonl` に記録
- ステータスラインで現在のセッションコスト + 過去のセッションコストを合算表示

## ファイル構成

```
install.sh             # インストール/アンインストールスクリプト
statusline.sh          # HUDメインスクリプト（ステータスラインで実行）
fetch-plan-usage.sh    # Anthropic OAuth APIプラン使用量取得 + キャッシュ
log-session.sh         # SessionEndフック - セッション指標をJSONLに記録
```

## 要件

- Claude Code（Maxプラン）
- `jq`, `curl`, `bc`
