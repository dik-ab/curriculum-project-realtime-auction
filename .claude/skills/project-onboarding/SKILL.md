---
name: project-onboarding
description: Lumina Marketリポジトリで最初に実行するオンボーディング。docsの読み順、前提の確認、受講者に質問すべきことを定める。初回セッションや「何から始めればいい?」と聞かれたときに使う。
---

# プロジェクトオンボーディング

Lumina Market(社内リアルタイムオークション)の開発を始める前に、このスキルの手順で前提をそろえます。

## 1. リポジトリの前提を確認する

- これは**仕様リポジトリのテンプレート**から作られた受講者のリポジトリです。実装コードをここに書いていきます。
- 構成: REST API + WebSocket + 締切スケジューラの1プロセス(フロントは任意で分離)。ローカルはdocker compose(必須はPostgreSQLのみ)で完結し、AWSアカウントは不要です。画像はローカルディスク保存です。
- 進め方: GitHub Issuesを M1 → M2 → M3 → M4 の順に、1 issue = 1 branch = 1 PR で進めます。advanced 2件(ADV-01 / ADV-02)は任意です。

## 2. docsをこの順で読む

| 順 | ファイル | 特に見るところ |
|---|---|---|
| 1 | `docs/requirements.md` | 用語集(入札単位 / 同額先着 / スナイプ / 自動延長 / 流札)、Must 1-11、非機能要件、スコープ外 |
| 2 | `docs/database.md` | 10テーブル、listings / tradesのステータス遷移図、bids.statusの意味論と不変条件 |
| 3 | `docs/api.md` | RESTエンドポイント一覧、入札の有効条件とエラーcode表(`BID_TOO_LOW` 等)、**WebSocketイベント一覧** |
| 4 | `docs/screens.md` | 出品詳細のリアルタイム要素、同時入札のsequenceDiagram(同額先着の仕組み) |
| 5 | `docs/infra.md` | composeスケルトン、環境変数、1プロセス前提とRedis pub/subへの発展 |
| 6 | `docs/development-flow.md` | ブランチ運用、DoD、競合テストの回し方、2ブラウザ確認 |

## 3. 受講者に質問すべきこと(実装開始前に必ず)

1. **スタック**: どの言語・フレームワークで実装しますか?(NestJS / Spring Boot / FastAPI / Laravel / Gin / Rails 等)WebSocketライブラリ(Socket.IO / gorilla/websocket / Action Cable等)も決めます。
2. **既習範囲**: SNSカリキュラム(Phase 08)のDM(WebSocket + Cookie/JWT handshake)は実装しましたか? 本プロジェクトのM3-01はその応用です。未実装なら先にSNSカリキュラムのDM章を確認します。
3. **issueの複製**: `scripts/setup_issues.sh` は実行済みですか? まだなら、このオンボーディングの後に `setup-github-project` スキルで複製します。
4. **フロントの作り込み**: 出品詳細(S-03)のリアルタイム表示はどこまで作りますか? 最低限、2ブラウザで価格更新が見える状態を推奨します(docs/screens.md)。

## 4. 最初の一歩

M1-01(環境構築)から着手します。issueへの着手手順は `issue-workflow` スキルに従ってください。

## 注意

- 仕様の解釈に迷ったら、推測せずdocsの該当セクションを引用して受講者と確認します。
- 入札・締切・延長のロジックは、必ず `bidding-consistency` スキルの実装パターン(条件付きUPDATE 1文)に従います。独自の楽観ロック等に変える場合はトレードオフをissueコメントに書いてから。
- スコープ外(決済、メール送信、社外ユーザー、評価機能)には手を出しません。
