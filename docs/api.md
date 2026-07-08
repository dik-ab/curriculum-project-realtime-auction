# API設計書 — Lumina Market

REST APIとWebSocketの両方を定義します。レスポンスはすべてJSON、パスの `:id` は数値ID、日時はISO 8601(UTC、例: `2026-07-06T09:00:00Z`)、金額はすべて整数(円)です。

## 認証

### REST API

SNSカリキュラムと同方式の **Cookie + JWT** です。

- `POST /api/auth/login` の成功時に、JWTをHttpOnly Cookie(`SameSite=Lax`、ローカルは `Secure` なしで可)として設定します。
- `signup` / `login` と監視用の `GET /healthz` 以外の**すべてのAPIは認証必須**です(社内サービスのためゲスト閲覧はありません)。未認証は `401`(code: `UNAUTHORIZED`)。
- admin専用API(`/api/admin/*`)をmemberが呼ぶと `403`(code: `FORBIDDEN`)です。

### WebSocket

- エンドポイントは `GET /ws`(HTTPからのUpgrade)。**handshake時にCookieのJWTを検証**します。**SNSカリキュラムのDMと同方式**です(Cookieはブラウザが自動送信するため、クライアント側の追加実装は不要)。
- 未認証・JWT不正の接続は拒否します(handshakeを401で失敗させる、または接続直後にclose code `4401` で切断。採った方式をPRに明記)。
- 接続後のイベントは「WebSocketイベント一覧」を参照してください。

## RESTエンドポイント一覧

### ヘルスチェック

| メソッド | パス | 認証 | Milestone | 役割 |
|---|---|---|---|---|
| `GET` | `/healthz` | 不要 | M1 | ヘルスチェック(監視・起動確認用。`200` を返すのみ) |

### 認証

| メソッド | パス | 認証 | Milestone | 役割 |
|---|---|---|---|---|
| `POST` | `/api/auth/signup` | 不要 | M1 | サインアップ。`@lumina.example` 以外は `400`(DOMAIN_NOT_ALLOWED) |
| `POST` | `/api/auth/login` | 不要 | M1 | ログイン(Cookie + JWT発行) |
| `POST` | `/api/auth/logout` | 必要 | M1 | ログアウト(Cookie破棄) |
| `GET` | `/api/auth/me` | 必要 | M1 | 自分の情報(id / name / email / role) |

### カテゴリ

| メソッド | パス | 認証 | Milestone | 役割 |
|---|---|---|---|---|
| `GET` | `/api/categories` | 必要 | M1 | 一覧(sort_order昇順) |
| `POST` | `/api/admin/categories` | admin | M1 | 作成(名前重複は `409`) |
| `PATCH` | `/api/admin/categories/:id` | admin | M1 | 更新 |
| `DELETE` | `/api/admin/categories/:id` | admin | M1 | 削除(出品から参照済みなら `409`) |

### 出品

| メソッド | パス | 認証 | Milestone | 役割 |
|---|---|---|---|---|
| `POST` | `/api/listings` | 必要 | M1 | 作成。`publish: true` で作成と同時に公開、falseで `draft` |
| `GET` | `/api/listings` | 必要 | M1 | 一覧・検索(`keyword` / `category_id` / `status`(既定 `active`)/ `sort`(`newest` / `ending_soon` / `popular`、既定 `newest`)/ `page` / `per_page`(既定20、最大100)) |
| `GET` | `/api/listings/:id` | 必要 | M1 | 詳細(画像・カテゴリ・出品者・現在価格を含む) |
| `PATCH` | `/api/listings/:id` | 出品者 | M1 | 編集(draft中は自由。active中は入札0件のときのみ。入札ありは `409`) |
| `POST` | `/api/listings/:id/publish` | 出品者 | M1 | 公開(`draft → active`)。ends_atが公開時点から24h〜7日の範囲外なら `400` |
| `POST` | `/api/listings/:id/cancel` | 出品者 | M1 | 取消(`draft / active(入札0件) / suspended → cancelled`。入札ありは `409`) |
| `POST` | `/api/listings/:id/images` | 出品者 | M1 | 画像アップロード(multipart。JPEG/PNG/WebP、5MB、最大4枚。5枚目は `400`) |
| `DELETE` | `/api/listings/:id/images/:imageId` | 出品者 | M1 | 画像削除(編集可能な状態のときのみ) |
| `POST` | `/api/admin/listings/:id/suspend` | admin | M1 | 停止(`active → suspended`。body: `{"reason": "..."}`) |
| `POST` | `/api/admin/listings/:id/unsuspend` | admin | M1 | 停止解除(`suspended → active`。ends_at超過時は解除せず終了処理) |

### 入札・状態復元

| メソッド | パス | 認証 | Milestone | 役割 |
|---|---|---|---|---|
| `POST` | `/api/listings/:id/bids` | 必要 | M2 | 入札。有効条件と同時実行の扱いは後述(本プロジェクトの核心) |
| `GET` | `/api/listings/:id/bids` | 必要 | M2 | 入札履歴(新しい順、ページネーション) |
| `GET` | `/api/listings/:id/state` | 必要 | M3 | **再接続時の状態復元**。現在価格・入札件数・ends_at・version・最新入札・閲覧人数を1回で返す |

### ウォッチリスト

| メソッド | パス | 認証 | Milestone | 役割 |
|---|---|---|---|---|
| `PUT` | `/api/listings/:id/watch` | 必要 | M4 | ウォッチ追加(冪等。二重追加でも `204`) |
| `DELETE` | `/api/listings/:id/watch` | 必要 | M4 | ウォッチ解除(冪等) |
| `GET` | `/api/me/watches` | 必要 | M4 | ウォッチ中の出品一覧 |

### マイページ

| メソッド | パス | 認証 | Milestone | 役割 |
|---|---|---|---|---|
| `GET` | `/api/me/listings` | 必要 | M2 | 自分の出品一覧(`status` で絞り込み。出品中/履歴) |
| `GET` | `/api/me/bids` | 必要 | M2 | 入札中・入札した出品一覧(出品ごとに自分の最高入札と勝ち負けを含む) |
| `GET` | `/api/me/trades` | 必要 | M4 | 自分が当事者の取引一覧 |

### 取引

| メソッド | パス | 認証 | Milestone | 役割 |
|---|---|---|---|---|
| `GET` | `/api/trades/:id` | 当事者 | M4 | 取引詳細(第三者は `403`) |
| `PATCH` | `/api/trades/:id` | 当事者 | M4 | ステータス遷移(`{"status":"handover"}` 等。`completed` は落札者のみ。不正遷移は `409`) |
| `GET` | `/api/trades/:id/comments` | 当事者 | M4 | コメント一覧 |
| `POST` | `/api/trades/:id/comments` | 当事者 | M4 | コメント投稿(相手方に `trade_comment` 通知) |

### 通知

| メソッド | パス | 認証 | Milestone | 役割 |
|---|---|---|---|---|
| `GET` | `/api/notifications` | 必要 | M2 | 通知一覧(`unread=true` で未読のみ。未読件数 `unread_count` を含む) |
| `PATCH` | `/api/notifications/:id/read` | 必要 | M2 | 既読化(read_at記録) |
| `POST` | `/api/notifications/read-all` | 必要 | M2 | 全既読化 |

### 代理入札(Should)

| メソッド | パス | 認証 | Milestone | 役割 |
|---|---|---|---|---|
| `PUT` | `/api/listings/:id/proxy-bid` | 必要 | M4 | 上限額の登録・更新(`{"max_amount": 5000}`)。出品者本人は `422`(SELF_BID_FORBIDDEN) |
| `DELETE` | `/api/listings/:id/proxy-bid` | 必要 | M4 | 登録解除 |

## 主要APIの入出力例

以下の例とWebSocketイベント例は、すべて**同一のシナリオ**を表しています: 出品12「27インチモニター」(開始価格3,000円、入札単位100円、`ends_at: 2026-07-06T09:02:00Z`、version 5)に、田中さんが3,000円で初回入札済み(bid 500)。締切2分前の `2026-07-06T09:00:00Z` に佐藤さんが3,100円で入札(bid 501)して成立し、残り3分以下のため**同一UPDATE文内で自動延長**が発生しました(`ends_at` は3分延長されて `09:05:00Z`、`extended_count` は0→1、`version` はこのUPDATE 1回分の+1で5→6)。

### POST /api/listings/:id/bids(入札)

リクエスト:

```json
{ "amount": 3100 }
```

レスポンス(`201` 成立時):

```json
{
  "bid": { "id": 501, "listing_id": 12, "amount": 3100, "status": "winning", "created_at": "2026-07-06T09:00:00Z" },
  "listing": {
    "id": 12,
    "current_price": 3100,
    "bids_count": 2,
    "ends_at": "2026-07-06T09:05:00Z",
    "extended_count": 1,
    "version": 6
  },
  "buyout": false
}
```

即決が成立した場合は `"buyout": true` となり、`listing.status` は `sold` です。

#### 入札の有効条件(requirements.md Must-5と同一。こちらにはエラーcodeを併記)

| # | 条件 | 満たさない場合のcode | HTTP |
|---|---|---|---|
| 1 | `status = 'active'`(draft / suspended / cancelled / ended / sold でない) | `AUCTION_NOT_ACTIVE` | 422 |
| 2 | DBの `now()` が `ends_at` より前 | `AUCTION_ENDED` | 422 |
| 3 | 入札者 ≠ 出品者 | `SELF_BID_FORBIDDEN` | 422 |
| 4 | 入札者 ≠ 現在の最高入札者 | `ALREADY_WINNING` | 422 |
| 5 | `bids_count = 0` なら `amount ≥ start_price`、それ以外は `amount ≥ current_price + bid_increment` | `BID_TOO_LOW` | 422 |

- `BID_TOO_LOW` のレスポンスには、次に有効な最低額を含めます: `{"message":"入札額が不足しています(最低3,200円)","code":"BID_TOO_LOW","minimum_amount":3200}`。
- `buyout_price` が設定されており `amount ≥ buyout_price` の場合は**即決**です。`current_price = buyout_price`、bidsには `amount = buyout_price` で記録し、落札後処理(trades作成・通知・`auction_ended` 配信)まで行います。
- 判定と更新は**1文の条件付きUPDATE**で行い、同額の同時入札は先にUPDATEに成功した方が勝ちます(後着は条件を満たさなくなり `BID_TOO_LOW`)。実装パターンは `.claude/skills/bidding-consistency/SKILL.md` が正です。
- 自動延長: 成立時に `ends_at - now() ≤ 3分` かつ `extended_count < 10` なら `ends_at` を3分延長し `extended_count` を+1します(同一UPDATE文内)。

### GET /api/listings/:id/state(再接続時の状態復元)

WebSocket切断中の変化に追いつくためのAPIです。再接続後、クライアントはまずこれを呼んで表示を最新化し、以降はイベントで差分更新します。

レスポンス(`200`):

```json
{
  "listing_id": 12,
  "status": "active",
  "current_price": 3100,
  "bids_count": 2,
  "ends_at": "2026-07-06T09:05:00Z",
  "extended_count": 1,
  "version": 6,
  "viewer_count": 4,
  "my_bid_status": "outbid",
  "latest_bids": [
    { "id": 501, "bidder_name": "佐藤", "amount": 3100, "status": "winning", "created_at": "2026-07-06T09:00:00Z" },
    { "id": 500, "bidder_name": "田中", "amount": 3000, "status": "outbid", "created_at": "2026-07-06T08:59:30Z" }
  ]
}
```

- `my_bid_status` は認証ユーザー自身の立場(`winning` / `outbid` / `won` / `lost` / 入札していなければ `null`)。
- `latest_bids` は新しい順に最大20件。`version` はUI側で「古いイベントを適用しない」判定に使えます(任意)。

## WebSocketイベント一覧

すべてのイベントはJSONテキストフレーム1件 = 1イベントで、`{"event": "...", "data": {...}}` の形に統一します。イベント名・方向・ペイロードは下表が**正**であり、実装(サーバー・クライアント・テスト)とスキル(`bidding-consistency`)はこの表と完全に一致させます。

| イベント名 | 方向 | 配信先 | 発生タイミング | ペイロード(dataのJSON例) |
|---|---|---|---|---|
| `join` | client → server | — | 出品詳細を開いたとき(roomへの参加要求) | `{"listing_id": 12}` |
| `leave` | client → server | — | 出品詳細を離れたとき(切断時はサーバーが自動離脱処理) | `{"listing_id": 12}` |
| `price_updated` | server → client | room(`listing:12`)全員 | 入札成立時 | `{"listing_id": 12, "current_price": 3100, "bids_count": 2, "version": 6, "bid": {"id": 501, "bidder_name": "佐藤", "amount": 3100, "created_at": "2026-07-06T09:00:00Z"}}` |
| `outbid` | server → client | 抜かれた入札者本人の全接続 | 最高入札者が入れ替わったとき | `{"listing_id": 12, "title": "27インチモニター", "your_amount": 3000, "current_price": 3100, "minimum_amount": 3200}` |
| `auction_extended` | server → client | room全員 | 自動延長が発生したとき | `{"listing_id": 12, "ends_at": "2026-07-06T09:05:00Z", "extended_count": 1, "version": 6}`(延長は入札と同一UPDATEのため、`version` は同時に配信される `price_updated` と同じ値) |
| `auction_ended` | server → client | room全員 | 締切処理・即決で確定したとき | `{"listing_id": 12, "result": "sold", "final_price": 3100, "winner_id": 8, "winner_name": "佐藤", "trade_id": 3, "version": 7}`(流札は `{"listing_id": 12, "result": "unsold", "final_price": null, "winner_id": null, "winner_name": null, "trade_id": null, "version": 7}`) |
| `viewer_count` | server → client | room全員 | join / leave / 切断で人数が変わったとき | `{"listing_id": 12, "count": 4}` |

運用ルール:

- roomのキーは `listing:<id>` に統一します。1接続が複数roomにjoinしても構いません(一覧画面での利用は想定外ですが禁止もしません)。
- 存在しない・`draft` の出品への `join` は無視またはエラーフレーム(`{"event":"error","data":{"message":"...","code":"NOT_FOUND"}}`)とします。採った方式をPRに明記してください。
- `outbid` はroom配信では**ありません**。抜かれた本人がそのページを見ていなくても届くよう、ユーザーID→接続の対応表(user registry)から本人の全接続に送ります。あわせてnotificationsレコード(type: `outbid`)も作成します(通知はWebSocketを受け取れなかった場合の受け皿です)。
- イベントの配信順は保証しますが、**到達は保証しません**(切断中は失われます)。クライアントは再接続時に `GET /api/listings/:id/state` で必ず追いつく設計にします。イベントを貯めて再送する仕組みは作りません。
- サーバーは1プロセス前提で、room管理はプロセス内メモリで構いません。複数プロセスに広げる場合の設計(Redis pub/sub)は [infra.md](infra.md) を参照してください(本プロジェクトのスコープ外)。

## エラー形式

エラーレスポンスは全エンドポイントで次の形に統一します(SNSカリキュラムの `{"message"}` 形式に `code` を追加したものです)。

```json
{
  "message": "入札額が不足しています(最低3,200円)",
  "code": "BID_TOO_LOW"
}
```

| code | HTTPステータス | 例 |
|---|---|---|
| `VALIDATION_ERROR` | 400 | 必須項目欠落、金額が下限未満、ends_atが24h〜7日の範囲外、画像の形式・サイズ・枚数超過 |
| `DOMAIN_NOT_ALLOWED` | 400 | サインアップのメールが `@lumina.example` 以外 |
| `UNAUTHORIZED` | 401 | 未ログイン、JWT不正・期限切れ(WebSocketのhandshake拒否も同義) |
| `FORBIDDEN` | 403 | admin APIをmemberが呼んだ、他人の出品の編集・取消、取引の第三者アクセス |
| `NOT_FOUND` | 404 | リソースが存在しない、削除済み |
| `EMAIL_TAKEN` | 409 | サインアップのメール重複 |
| `CONFLICT` | 409 | 入札が付いた出品の編集・取消、カテゴリ名重複・使用中カテゴリの削除、取引の不正遷移、公開済み出品の再publish |
| `BID_TOO_LOW` | 422 | 入札額が「開始価格」または「現在価格 + 入札単位」未満(同額先着で負けた場合を含む)。`minimum_amount` を併記 |
| `AUCTION_NOT_ACTIVE` | 422 | draft / suspended / cancelled / ended / sold への入札 |
| `AUCTION_ENDED` | 422 | 締切時刻(ends_at)以降の入札。**判定はDBの now()** |
| `SELF_BID_FORBIDDEN` | 422 | 自分の出品への入札(代理入札の登録を含む) |
| `ALREADY_WINNING` | 422 | 現在の最高入札者による再入札 |
| `INTERNAL_ERROR` | 500 | 想定外のサーバーエラー |

- codeは**大文字スネークケース**で固定です。クライアントはmessage(表示用・変更されうる)ではなくcodeで分岐します。
- 400/422の使い分け: 入力の形が悪いものは `400`、形は正しいがオークションのドメインルールで拒否されるものは `422` です。
- バリデーション詳細を返したい場合は、SNSカリキュラムと同様に `fields` を追加しても構いません。
