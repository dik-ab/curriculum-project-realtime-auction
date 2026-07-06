---
name: setup-github-project
description: scripts/setup_issues.sh を使って受講者自身のリポジトリにラベル・マイルストーン・issueを複製する手順。テンプレートからリポジトリを作った直後、または「issueをセットアップして」と言われたときに使う。
---

# GitHubプロジェクトセットアップ

テンプレートから作った受講者のリポジトリに、ラベル5種・マイルストーンM1〜M4・22件のissue(20 + advanced 2)を複製します。advanced 2件はどのマイルストーンにも属しません(任意課題のため)。

## 前提確認

```bash
gh --version          # GitHub CLI が入っているか
jq --version          # jq が入っているか
gh auth status        # 認証済みか。未認証なら: gh auth login
gh repo view --json nameWithOwner -q .nameWithOwner   # いまのリポジトリを確認
```

- 実行対象は**受講者自身のリポジトリ**です(テンプレート元の dik-ab/curriculum-project-realtime-auction ではありません。スクリプトはテンプレート元を指定するとエラーで止まります)。
- issue作成権限(リポジトリのwrite権限)が必要です。

## 実行

リポジトリのルートで:

```bash
./scripts/setup_issues.sh                # カレントのリポジトリに複製
./scripts/setup_issues.sh you/your-repo  # 明示指定する場合(owner/repo形式)
```

## スクリプトの挙動(受講者に説明するとき用)

- `scripts/issues.json` を読み、ラベル → マイルストーン → issue の順に作成します。
- **冪等**です: ラベルは `--force` で上書き、マイルストーンとissueは**同名が存在すればスキップ**するので、途中で失敗しても再実行すれば続きから復旧します。
- ラベル: `feature`(緑) / `chore`(グレー) / `docs`(青) / `test`(黄) / `advanced`(紫)
- マイルストーン: M1 出品と検索 / M2 入札コア / M3 リアルタイム / M4 取引と仕上げ
- ADV-01 / ADV-02 はマイルストーンなしで作成されます。

## 完了確認

```bash
gh label list
gh api "repos/{owner}/{repo}/milestones" -q '.[].title'
gh issue list --limit 30   # M1-01〜ADV-02 が並ぶこと(22件)
```

## よくあるエラー

| 症状 | 対処 |
|---|---|
| `gh: command not found` | GitHub CLIをインストール(https://cli.github.com) |
| テンプレート元を指定してエラー | 自分のリポジトリ(owner/repo)を指定し直す |
| `HTTP 404` | `$1` の owner/repo が誤り、またはリポジトリ未作成 |
| `Validation Failed` (milestone) | 同名マイルストーンが既存 → スクリプトはスキップするので再実行でOK |
| issueが重複した | タイトル完全一致で判定しているため、タイトルを手で変えた場合は再作成される。不要な方を `gh issue close` で閉じる |
