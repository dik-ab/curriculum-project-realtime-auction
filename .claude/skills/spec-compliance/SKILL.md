---
name: spec-compliance
description: PR作成前の仕様適合チェック。実装をdocs/requirements.md・database.md・api.mdと突合し、チェックリストを出力する。「PRを出す前に確認して」「仕様に合っているか見て」と言われたときに使う。
---

# 仕様適合チェック(PR前)

実装diffを `docs/` と突き合わせ、結果をチェックリストとしてPR本文に貼れる形で出力します。

## 手順

1. `git diff main...HEAD` で変更範囲を把握します。
2. 変更が触れる領域ごとに、下の突合項目を**docsの該当箇所を開きながら**確認します。記憶で判定しないこと。
3. 結果を「チェックリスト出力形式」でまとめ、NGがあれば修正してから再チェックします。

## 突合項目

### DB(docs/database.md)

- [ ] テーブル名・カラム名が定義表と一致(10テーブル: users / categories / listings / listing_images / bids / watches / trades / trade_comments / notifications / proxy_bids)
- [ ] ステータス値が遷移図と一致: listings = `draft / active / suspended / ended / sold / cancelled`、trades = `initiated / handover / completed`、bids = `winning / outbid / won / lost`
- [ ] 遷移図にない遷移(例: `sold → active`、`completed → handover`)を作っていない
- [ ] bidsの不変条件を壊していない: `winning` は常に0〜1件、`winning` のamount = `current_price`、bidder = `current_winner_id`
- [ ] `trades.listing_id` のUNIQUE、`bids` の INDEX(listing_id, amount DESC)、`listings` の INDEX(status, ends_at) がmigrationに存在する
- [ ] カウンタ・versionの更新が相対UPDATE(`bids_count = bids_count + 1`)になっている
- [ ] 金額カラムがすべて整数(円)で、浮動小数点を使っていない

### API(docs/api.md)

- [ ] パス・メソッドがエンドポイント一覧と一致(`/api/...` / `/api/admin/...` / `/ws`)
- [ ] エラーが `{"message","code"}` 形式で、codeが表にある値(大文字スネークケース: VALIDATION_ERROR / DOMAIN_NOT_ALLOWED / UNAUTHORIZED / FORBIDDEN / NOT_FOUND / EMAIL_TAKEN / CONFLICT / BID_TOO_LOW / AUCTION_NOT_ACTIVE / AUCTION_ENDED / SELF_BID_FORBIDDEN / ALREADY_WINNING / INTERNAL_ERROR)
- [ ] 入札の有効条件5項目(active / 締切前 / 出品者でない / 現勝者でない / 金額)が表のcode・HTTPステータスどおり
- [ ] `BID_TOO_LOW` のレスポンスに `minimum_amount` が入っている
- [ ] WebSocketイベント名・方向・ペイロードのキーが「WebSocketイベント一覧」と完全一致(`price_updated` / `outbid` / `auction_extended` / `auction_ended` / `viewer_count` / `join` / `leave`)
- [ ] `outbid` がroom配信ではなく本人の接続への個別送信になっている
- [ ] WebSocketのhandshakeでCookieのJWTを検証し、未認証を拒否している

### 要件(docs/requirements.md)

- [ ] 対象issueの受入条件をすべて満たす(1つずつ引用して判定)
- [ ] 入札・締切・延長が絡む変更に同時実行テスト(並列入札 / 締切競合)がある
- [ ] 締切判定がDBの `now()` 基準で、アプリサーバーの時計に依存していない
- [ ] 自動延長が「+3分、累計30分(10回)上限、入札と同一UPDATE文内」になっている
- [ ] サインアップのドメイン制限(@lumina.example)が効いている
- [ ] スコープ外(決済、メール送信、評価機能等)に踏み込んでいない

## チェックリスト出力形式

```markdown
## 仕様適合チェック(spec-compliance)
- 対象issue: #N
- 参照した仕様: docs/api.md「...」, docs/database.md「...」
- [x] 合格した項目(根拠: 仕様の引用 or テスト名)
- [ ] NG項目(何がどう違うか、修正方針)
```

NGが1つでも残っている状態でPRを出してはいけません。仕様側の誤りだと考える場合は、issueコメントで根拠を示してからdocsを修正します。
