# Claude Code HUD

Claude Codeのステータスラインに使用量情報をリアルタイム表示するカスタムHUD。

[English](../README.md) | [한국어](README.ko.md) | [中文](README.zh.md)

## プレビュー

```
Opus 4.6 (1M context) | 5m 0s (api:3m 0s) | $1.23 | d:$4.56 m:$78.90 | in:45.2K out:12.8K
ctx  [███████░░░░░░░░░░░░░] 35%
5h   [░░░░░░░░░░░░░░░░░░░░]  4%  reset 3h 30m
week [████░░░░░░░░░░░░░░░░] 22%  reset 4d 19h
```

| 行 | 内容 |
|----|------|
| 1 | モデル名、セッション時間(API時間)、セッションコスト、日次/月次累計コスト、入出力トークン |
| 2 | コンテキストウィンドウ使用率バー |
| 3 | 5時間プラン上限使用率 + リセットタイマー |
| 4 | 週間プラン上限使用率 + リセットタイマー |

- バーの色: 緑(<50%) → 黄(50-79%) → 赤(80%+)
- セッションコスト: 現在のセッションのみ表示（黄色）
- `d:` / `m:`: 過去の完了セッションの累計コスト（日次 / 月次）

## インストール

### macOS / Linux

```bash
git clone https://github.com/kangnam7654/claude-code-hud.git
cd claude-code-hud
./install.sh
```

アンインストール: `./install.sh --uninstall`

### Windows (PowerShell 7+)

```powershell
git clone https://github.com/kangnam7654/claude-code-hud.git
cd claude-code-hud\win
.\install.ps1
```

アンインストール: `.\install.ps1 -Uninstall`

両インストーラーは `~/.claude/settings.json` を自動設定します。インストール後、Claude Codeの再起動が必要です。

## 仕組み

### ステータスライン (`statusline.sh`)

Claude Codeがstdinで送信するセッションJSONを読み取り、ダッシュボードをレンダリング:
- セッション指標（コスト、時間、トークン）
- コンテキストウィンドウ使用率バー
- プラン使用率バー + リセットタイマー（キャッシュされたAPIデータ）
- 過去セッションの日次/月次累計コスト（`usage-log.jsonl` ベース）
- 更新ごとにセッションスナップショットを保存（SessionEndフック用）

### プラン使用量 (`fetch-plan-usage.sh`)

- `api.anthropic.com/api/oauth/usage` OAuth API呼び出し
- トークンソース: `~/.claude/.credentials.json` またはmacOS Keychain
- 30秒キャッシュ (`~/.claude/plan-usage-cache.json`) でステータスラインの速度に影響なし
- キャッシュが古くなるとバックグラウンドで自動更新

### セッションログ (`log-session.sh`)

- SessionEndフックで `statusline.sh` が保存したセッションスナップショットを読み取りログに記録
- コスト/トークン/時間指標を `~/.claude/usage-log.jsonl` にJSONLで保存
- 全プロジェクトの使用量が一つのログファイルにグローバルに蓄積

## ファイル構成

```
statusline.sh          # HUDメインスクリプト（stdin JSON解析、出力レンダリング）
fetch-plan-usage.sh    # OAuth APIプラン使用量取得 + バックグラウンドキャッシュ
log-session.sh         # SessionEndフック - セッション終了時に指標をJSONLに記録
install.sh             # インストール/アンインストールスクリプト（macOS/Linux）
lib/hud-utils.sh       # 共有ユーティリティ関数（statusline.shがsource）
win/                   # Windows PowerShellポート（statusline, fetch, log, install）
test/                  # BATSテストスイート（35テスト）
```

## テスト

```bash
./test/bats/bin/bats test/*.bats
```

## 要件

- Claude Code（Maxプラン）
- macOS/Linux: `jq`, `curl`, `bc`
- Windows: PowerShell 7+（`winget install Microsoft.PowerShell`）

## ライセンス

[MIT](../LICENSE)
