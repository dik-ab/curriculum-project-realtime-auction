# 開発の進め方 — Lumina Market

実務プロジェクト応用編の共通ルール(issue駆動 + AI駆動)に、このプロジェクト特有の「競合テストの回し方」「WebSocketの手動確認」を加えたガイドです。

## 共通ルール

- **マイルストーン順**(M1 → M2 → M3 → M4)に、各マイルストーン内はissue番号順に進めます。M3のリアルタイム配信はM2の入札コアの上に積み上がるため、飛ばすと後で詰まります。
- **1 issue = 1 branch = 1 PR**。ブランチ名は `feature/<issue番号>-<slug>`(例: `feature/6-bid-api`)。
- PRは `.github/PULL_REQUEST_TEMPLATE.md` に従い、本文に `Closes #<issue番号>` を書きます。
- **Definition of Done(全issue共通)**:
  1. issueのタスク・受入条件をすべて満たしている
  2. テストを書き、ローカルで通っている(`docker compose up` した状態で)
  3. `docs/` の仕様(テーブル名・エンドポイント・ステータス値・エラーcode・WebSocketイベント名)と一致している(`.claude/skills/spec-compliance` でチェック)
  4. セルフレビュー(自分のPRのdiffを他人のつもりで読む)を済ませている
- **AI駆動の型**: 着手時は `.claude/skills/issue-workflow`、PR前は `.claude/skills/spec-compliance` を使います。初回は `.claude/skills/project-onboarding` から。入札の整合性・締切競合・イベント設計の判断では `.claude/skills/bidding-consistency` を参照します。

## このプロジェクト特有: 競合テストの回し方

Lumina Marketの品質は「同時に叩いても正しい」ことがすべてです。入札・締切・延長に触れるissue(M2-01、M2-05、M3-04、M4-03)では、次の型でテストを書きます。

1. **不変条件を先に書き出す**: テスト後にassertする条件を実装前に決めます。
   - `current_price` = bidsの最高額、かつ単調増加(下がった履歴がない)
   - `winning` の入札は常に0件または1件。`sold` 後は `won` が正確に1件
   - `bids_count` = bidsの行数
   - `ends_at` 以降に `created_at` を持つ入札が存在しない
2. **並列実行の道具を決める**: スタックの並行プリミティブ(goroutine / Promise.all / ExecutorService / ThreadPoolExecutor等)で、**同一出品に対して100リクエストを同時に**投げます。HTTP経由が難しければサービス層の関数を直接並列に呼んでも構いません(どちらでやったかをPRに明記)。
3. **assertは終了後の静止状態に対して行う**: 実行中の途中経過は不定で構いません。全リクエスト完了後にDBを読み、1の不変条件をすべて検証します。「成功した入札数 + BID_TOO_LOW等の拒否数 = 100」も確認します。
4. **落ちたら喜ぶ**: 競合テストは非決定的に落ちることがあります。落ちた1回はバグの証拠です。「たまに落ちるから」でretryやsleepでごまかさず、条件付きUPDATEに寄せて原因を潰します。

## WebSocketの手動確認

自動テストに加えて、**ブラウザを2つ並べる**確認をM3の各issueで行ってください(これがこのプロジェクトの一番楽しい瞬間です)。

```bash
# ウィンドウA: 通常ログインで出品詳細を開く
# ウィンドウB: シークレットウィンドウで別ユーザーとしてログインし、同じ出品を開く
# → Bで入札すると、Aの現在価格・履歴・閲覧人数が更新されること(リロードなし)
```

- コマンドラインで確認する場合は `websocat` が便利です(接続例は `docs/screens.md`)。
- 締切・延長の確認は、`ends_at` を2〜3分後に設定したテスト出品を作ると待ち時間が短くて済みます。テストコードでは時刻注入(クロックの抽象化)を推奨します(`bidding-consistency` 参照)。

## つまずいたら

- 入札の整合性・締切競合・自動延長・イベント設計: `.claude/skills/bidding-consistency/SKILL.md`
- WebSocketのCookie + JWT handshake: SNSカリキュラムのDM実装(自分のSNSリポジトリ)を見直すのが最短です。同方式です。
- 仕様の矛盾を見つけたら: 実装を仕様に合わせるのが原則ですが、仕様書側の誤りだと考えた場合は、issueコメントに根拠を書いてから自分のリポジトリの `docs/` を直して構いません(実務のADRと同じ習慣です)。
