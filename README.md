# Lumina Market — 社内リアルタイムオークション(実務プロジェクト応用編 Project 05)

架空のビューティーテック企業「株式会社Lumina」の社内オークション/フリマサービスを、issue駆動 + AI駆動(Claude Code / Codex)で開発する実務演習プロジェクトです。

このリポジトリは**仕様リポジトリ**です。要件定義書・DB設計書・API設計書(WebSocketイベント仕様を含む)・画面定義書・インフラ設計書と、実装を進めるためのGitHub Issues一式(複製スクリプト付き)が入っています。実装コードは、受講者自身がこのテンプレートから作った自分のリポジトリに書きます。

## ストーリー

Lumina社は社員150人に成長しました。社内Slackには「引っ越すのでモニター譲ります」「加湿器欲しい人いませんか」という投稿が日々流れていますが、タイムラインに埋もれて誰にも届かないまま流れていきます。

そこで総務チームの発案で、福利厚生として社内オークション/フリマ「**Lumina Market**」を作ることになりました。せっかく作るなら盛り上がる仕掛けが欲しい——入札の攻防が**リアルタイム**に見えるオークション形式にします。

技術的な本丸は、SNS開発カリキュラムのDMで触れたWebSocketを「業務ロジック」に昇格させることです。同時に飛んでくる入札のうち**高い方だけが勝つ**整合性、負けた入札者への即時通知、終了間際のスナイプ入札への自動延長、締切処理とラスト入札の競合——「リアルタイム」と「正しさ」を両立させる設計を、テストで証明しながら作ります。

## 学べること

- 同時入札の整合性: 条件付きUPDATEで「現在価格 + 入札単位以上、同額は先着」を保証する(並列100入札の競合テスト付き)
- リアルタイムブロードキャスト: 出品ごとのroomに現在価格・入札履歴・残り時間・閲覧人数を配信する
- WebSocketのCookie + JWT認証(SNSカリキュラムのDMと同方式)と、切断→再接続時の状態復元
- スナイプ対策の自動延長(終了3分前以降の入札で+3分、累計30分上限)のサーバー側締切管理
- スケジューラによる締切処理と、締切とラスト入札の競合の扱い(締切後の入札は必ず拒否)
- 画像アップロード(ローカル保存)、検索・ソート、落札後の取引フロー

## 使い方

1. このリポジトリ右上の **Use this template** から自分のリポジトリを作成します(Public推奨)。
2. 自分のリポジトリをcloneし、`gh auth login` を済ませたうえで issue複製スクリプトを実行します。

   ```bash
   ./scripts/setup_issues.sh <your-account>/<your-repo>
   ```

   ラベル・マイルストーン(M1〜M4)・22件のissueが複製されます。スクリプトは冪等なので、途中で失敗しても再実行できます。
3. `docs/` の仕様書を読み(順番は `CLAUDE.md` 参照)、**M1-01から順に** 1 issue = 1 branch = 1 PR で実装を進めます。
4. 言語・フレームワークは自由です(カリキュラムで学んだ NestJS / Spring Boot / FastAPI / Laravel / Gin / Rails + React を推奨)。仕様はスタック非依存で書かれています。WebSocketライブラリ(Socket.IO、gorilla/websocket、Action Cable等)も自由です。

## AWSアカウントは不要です

このプロジェクトは**ローカル環境だけで完結**します。docker composeで必須なのはPostgreSQLだけで、出品画像もローカルのディスクに保存します。

| 本番想定 | ローカル代替 |
|---|---|
| RDS(PostgreSQL) | PostgreSQL(docker compose) |
| S3 + presigned URL(画像) | ローカルディスク保存(`uploads/`) |
| ElastiCache Redis(複数台のpub/sub) | 不要(API 1プロセス前提。設計上の発展として `docs/infra.md` に記載) |

唯一の例外は発展課題 ADV-02(画像基盤のS3 + Terraform化)で、実際にAWSへ適用する部分は**任意**です。適用する場合はコストと消し忘れに注意してください(`docs/infra.md` 参照)。

## ドキュメント一覧

| ドキュメント | 内容 |
|---|---|
| [docs/requirements.md](docs/requirements.md) | 要件定義書(用語集、機能要件Must/Should/Could、非機能要件、ユースケース) |
| [docs/database.md](docs/database.md) | DB設計書(ER図、10テーブルの定義表、インデックス方針、listings/tradesの状態遷移図、bidsのstatus意味論) |
| [docs/api.md](docs/api.md) | API設計書(RESTエンドポイント一覧、WebSocketイベント一覧、認証、JSON例、エラーcode表) |
| [docs/screens.md](docs/screens.md) | 画面定義書(画面一覧、出品詳細のリアルタイム要素、同時入札のシーケンス図) |
| [docs/infra.md](docs/infra.md) | インフラ設計書(docker compose構成、本番想定AWS構成図、ALBとWebSocketの注意点) |
| [docs/development-flow.md](docs/development-flow.md) | 開発の進め方(issue駆動、ブランチ、PR、DoD、AI活用、競合テストの回し方) |

## 進め方の目安

全体で**4〜6週間**を想定しています。

| マイルストーン | テーマ | 目安 |
|---|---|---|
| M1: 出品と検索 | 認証(ドメイン制限)・出品CRUD・画像・カテゴリ・検索 | 1〜1.5週 |
| M2: 入札コア | 入札API(整合性)・即決・締切スケジューラ・通知モデル | 1〜1.5週 |
| M3: リアルタイム | WebSocket基盤・ブロードキャスト・自動延長・再接続復元 | 1〜1.5週 |
| M4: 取引と仕上げ | 取引フロー・ウォッチリスト・代理入札・CI・デモ | 1〜1.5週 |

## 前提と関連リンク

- 前提: SNS開発カリキュラム(Phase 08)とAI駆動開発の修了。特に**DMのWebSocket実装**(Cookie + JWTのhandshake検証)は本プロジェクトの土台です。
- 本プロジェクトは実務プロジェクト応用編の**選択プロジェクト**です。Project 01〜03(Reserve / ID / Notify)とは独立しており、どの順で着手しても構いません。
- AI駆動開発の型: `CLAUDE.md` / `AGENTS.md` と `.claude/skills/` を参照してください。入札の整合性で迷ったら `.claude/skills/bidding-consistency/SKILL.md` が羅針盤です。

## ライセンス

MIT License([LICENSE](LICENSE))
