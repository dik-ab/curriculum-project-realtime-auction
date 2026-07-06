---
name: bidding-consistency
description: 入札の整合性・締切競合・自動延長・WebSocketイベント設計の原則(Lumina Market固有)。入札API実装、二重勝者バグ、並列入札テスト、締切スケジューラ、自動延長、ブロードキャスト設計の相談を受けたときに使う。
---

# 入札整合性の設計原則

Lumina Marketの入札は「同時に来ても正しい」ことがすべてです。「入札は同時に飛んでくる」「締切処理は入札と同時に走る」の2つを設計の公理として扱います。仕様の正はdocs(api.md / database.md)です。

## 1. 守るべき不変条件

テストのassertは常にこの4つに帰着させます。1つでも破れる実装は誤りです。

1. **current_priceは単調増加**: 下がる更新は存在しない。常にbidsの最高額と一致する
2. **勝者は常に「最高額の先着」**: `winning` の入札は1出品につき0〜1件。同額なら先にDB更新に成功した方。`sold` 確定後は `won` が正確に1件(二重勝者なし)
3. **締切後の入札は存在しない**: `ends_at` 以降の `created_at` を持つ入札行がない(判定はDBの `now()`)
4. **カウンタは実数と一致**: `bids_count` = bidsの行数。`listings.current_winner_id` = `winning` 入札のbidder_id

## 2. 排他方式の比較と推奨

「現在価格より高い方だけ勝つ」を守る3方式の比較です。

| 観点 | 条件付きUPDATE(推奨) | SELECT FOR UPDATE | 楽観ロック(versionカラム) |
|---|---|---|---|
| 仕組み | 有効条件をWHERE句に書き、更新行数0なら拒否 | 行ロックを取ってから読み、アプリで検証してUPDATE | 読んだversionをWHEREに含めてUPDATE、0行なら再試行 |
| 同額先着の実現 | 自動的に満たす(後着は更新後の値で条件評価され不成立) | ロック順で満たす | 満たすが、負け側は再試行→再び負け、を自分で書く |
| check-then-act競合 | **構造的に起きない**(判定と更新が原子的) | ロック中は起きないが、ロック取得前のSELECTで判定すると起きる | versionが守るが再試行ロジックのバグ余地がある |
| ロック保持時間 | UPDATE 1文の間のみ(最短) | SELECT〜COMMITの間ずっと(外部I/Oを挟むと危険) | 短いが再試行でスループット低下 |
| 実装量 | WHERE句がやや複雑になるだけ | トランザクション境界の管理が必要 | 再試行ループ + 上限 + テストが必要 |
| 向く場面 | 判定材料が対象行だけで完結する(**本プロジェクトの入札はこれ**) | 複数行・複数テーブルを見て判断する(予約システムの空き枠等) | 競合が稀で、ユーザーに「他の人が更新しました」と再操作を促せる画面 |

> 本プロジェクトの推奨は**条件付きUPDATE**です。入札の有効条件(docs/api.md の5項目)はすべてlistingsの1行で判定できるため、WHERE句に押し込めます。`listings.version` カラムは楽観ロック用ではなく、イベントの世代識別(再接続復元・二重適用防止)用です。

## 3. 入札の実装パターン(条件付きUPDATE 1文)

判定・価格更新・自動延長を**1文**で行います。これが本プロジェクトの中心です。

```sql
UPDATE listings SET
  current_price     = $amount,
  current_winner_id = $bidder_id,
  bids_count        = bids_count + 1,
  ends_at = CASE WHEN ends_at - now() <= interval '3 minutes' AND extended_count < 10
                 THEN ends_at + interval '3 minutes' ELSE ends_at END,
  extended_count = CASE WHEN ends_at - now() <= interval '3 minutes' AND extended_count < 10
                        THEN extended_count + 1 ELSE extended_count END,
  version    = version + 1,
  updated_at = now()
WHERE id = $listing_id
  AND status = 'active'
  AND ends_at > now()
  AND seller_id <> $bidder_id
  AND (current_winner_id IS NULL OR current_winner_id <> $bidder_id)
  AND $amount >= CASE WHEN bids_count = 0 THEN start_price
                      ELSE current_price + bid_increment END
RETURNING current_price, bids_count, ends_at, extended_count, version;
```

- **1行更新できたら成立**: 同一トランザクション内で「旧 `winning` を `outbid` に更新(`WHERE listing_id = ? AND status = 'winning'`)」→「新規bidsをINSERT(`winning`)」→ COMMIT。COMMIT後に `price_updated` / `outbid` を配信します(配信はトランザクションの外)。
- **0行なら拒否**: どの条件で落ちたかを特定するため、その後に1回SELECTしてエラーcode(AUCTION_ENDED / SELF_BID_FORBIDDEN / ALREADY_WINNING / BID_TOO_LOW…)を決めます。このSELECTは**エラーメッセージ用**であり、判定には使いません(判定はUPDATEが済ませています)。
- 即決(`amount >= buyout_price`)の場合は、同じ考え方で `current_price = buyout_price`、`status = 'sold'` まで含めた条件付きUPDATEにし、成功時に締切処理と同じ後処理(trades作成・bids確定・通知・`auction_ended`)を行います。
- ORMを使う場合も、この形のUPDATEが発行されること(=先にSELECTで検証していないこと)を発行SQLのログで確認してください。

## 4. 締切とラスト入札の競合

締切スケジューラと入札APIは同じ行を取り合います。どちらも条件付きUPDATEなら競合は自然に解決します。

```sql
-- スケジューラ側(終了処理の先頭)
UPDATE listings SET status = CASE WHEN bids_count > 0 THEN 'sold' ELSE 'ended' END,
       version = version + 1, updated_at = now()
WHERE id = $id AND status = 'active' AND ends_at <= now()
RETURNING status, current_winner_id, current_price;
```

- 入札のWHERE句は `ends_at > now()`、締切のWHERE句は `ends_at <= now()`。**同じ行に対して両方が同時に成立することはない**ため、どちらかが必ず空振りします。これが「締切後の入札が勝つことはない」の証明です。
- **ends_atの再読込が必須**: スケジューラが「終了対象をSELECT→1件ずつ処理」する構造の場合、SELECT時点とUPDATE時点の間に自動延長でends_atが延びていることがあります。上記のように**UPDATEのWHERE句でends_atを再評価**すれば、延長済みの出品は空振りして次回スキャンに回ります。SELECTの結果を信じてstatusだけ更新する実装は誤りです。
- 後処理(trades作成・bids確定・通知・配信)は**UPDATEが1行返したときだけ**行います。スケジューラが多重起動しても、2回目は空振りするので後処理も走りません。さらに `trades.listing_id` のUNIQUEが最後の砦になります(docs/database.md)。
- bidsの確定も条件付きで: `UPDATE bids SET status='won' WHERE listing_id=$id AND status='winning'`、`UPDATE bids SET status='lost' WHERE listing_id=$id AND status='outbid'`。

## 5. 自動延長の実装

仕様(docs/requirements.md Must-8): 残り3分以下の入札成立で `ends_at + 3分`、累計10回(30分)上限。

- **入札と同一のUPDATE文内で行う**(3節のCASE式)。「入札成立→別文で延長」に分けると、その隙間に締切処理が滑り込み、延長されるはずだった出品が終了します。
- 延長の基準は「現在の `ends_at` に+3分」です(`now() + 3分` ではありません)。残り2分59秒での入札は残り5分59秒になります。
- 延長が起きたか判定するには、UPDATE前後の `extended_count`(RETURNINGで取得)を比較します。増えていたら `auction_extended` を配信します。
- テストは時刻を注入して書きます: 「残り3分1秒→延長なし」「残り3分ちょうど→延長」「残り2分59秒→延長」「extended_count=10→延長なし(入札は成立)」の境界4ケース。実時間のsleepで3分待つテストは書かないこと。

## 6. 並列100入札テストの書き方(M2-01)

非機能要件「並列100入札で不整合ゼロ」の検証手順です。

1. **Arrange**: `active` の出品を1件作る(start_price=1000、bid_increment=100、ends_atは十分先)。入札者ユーザーを100人(またはN人で各複数回)用意する。
2. **Act**: 100リクエストを**同時に**発行する。金額は「全員同額」と「ばらばら(1000〜11000)」の2パターンを両方やる。HTTP経由(実サーバー + 並列HTTPクライアント)か、サービス層関数の並列呼び出しかはスタックに合わせて選び、PRに明記する。DBコネクションプールが並列数より小さいと直列化されて意味が薄れるので、プールサイズ ≥ 20程度にする。
3. **Assert(終了後の静止状態に対して)**:
   - 1節の不変条件1・2・4がすべて成立(current_price = bidsの最高額、winningは1件、bids_count = 行数)
   - 成功数(201) + 拒否数(422) = 100。全員同額パターンでは成功はちょうど1件
   - current_priceの履歴が単調増加(bidsをcreated_at順に並べてamountが逆転していないこと。同時刻はid順)
4. **よくある不合格パターン**: 「事前SELECTで検証→UPDATE」(check-then-act。同額が2件とも成立する)/ `bids_count` をアプリで読んで+1して書き戻す(lost update)/ winningの付け替えを別トランザクションで行う(winningが一時的に2件になり、そこでテストが観測する)。
5. 競合テストが**たまに落ちる**のは実装のバグです。sleepやretryで安定させず、3節のパターンに寄せて直します。

## 7. WebSocketイベント設計

イベント名・方向・ペイロードの**正は docs/api.md の「WebSocketイベント一覧」**です。このスキルは設計判断だけを補足します(表とズレたらapi.mdが勝ちます)。

- イベントは `price_updated` / `outbid` / `auction_extended` / `auction_ended` / `viewer_count`(server→client)、`join` / `leave`(client→server)の7つで全部です。安易に増やさないこと(「残り時間の毎秒プッシュ」は作らない。クライアントがends_atから計算します)。
- **配信はDBコミットの後**: コミット前に配信すると、ロールバック時に「起きていない入札」が全員に見えます。逆(コミット後に配信が失敗)は再接続復元でリカバーできるので許容します。
- `price_updated` はroom(`listing:<id>`)へ、`outbid` は**抜かれた本人のuser registry経由で全接続へ**。この区別を崩さないこと(outbidをroomに流すと本人以外にも「あなたは抜かれました」が届く)。
- 1回の入札で送るイベントは「`price_updated`(room)+ 必要なら `auction_extended`(room)+ `outbid`(個人)」の最大3つ。この順で送ります。
- イベントは**失われる前提**で設計します(切断中は届かない)。クライアントの正は `GET /api/listings/:id/state` であり、イベントは差分の速報にすぎません。「イベントを全部受け取れたときだけ正しく表示できる」UIは設計ミスです。
- ペイロードには表示に必要な値をすべて入れ、受信側がAPIを叩き直さなくて済むようにします(ただし入札履歴の全量など大きいものは `/state` に任せます)。
