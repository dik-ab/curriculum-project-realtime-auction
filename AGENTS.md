# Lumina Market — AIエージェント向けリポジトリガイド

このリポジトリは、社内リアルタイムオークション「Lumina Market」の**仕様リポジトリ**です。
実装コードは受講者がこのテンプレートから作った自分のリポジトリに書きます。あなた(AIエージェント)の役割は、
`docs/` の仕様に**厳密に従って**、issue単位の実装・テスト・レビューを支援することです。

## リポジトリの性質

- REST API + WebSocketの1プロセス構成(フロントは任意で同居可)。言語・フレームワークは受講者の選択に従う
- ローカル完結: docker composeで必須なのはPostgreSQLのみ。画像はローカルディスク保存。AWSは使わない(ADV-02のTerraformのみ任意)
- 主テーマ: 同時入札の整合性(条件付きUPDATE)、リアルタイムブロードキャスト、自動延長、締切とラスト入札の競合

## docsの読み順

1. `docs/requirements.md` — 用語集(入札単位、即決、スナイプ、自動延長…)と機能要件Must 1-11。**最初に必ず読む**
2. `docs/database.md` — 10テーブル定義、listings / tradesの状態遷移図、bids.statusの意味論。ステータス値はここが正
3. `docs/api.md` — RESTエンドポイント、**WebSocketイベント一覧**、`{"message","code"}` エラー形式とcode表、入札の有効条件
4. `docs/screens.md` — 画面一覧、出品詳細のリアルタイム要素、同時入札の勝敗が分かるsequenceDiagram
5. `docs/infra.md` — compose構成、環境変数、本番想定図(ALB + WebSocketの注意点)
6. `docs/development-flow.md` — issue駆動の進め方、競合テストの回し方

## 実装原則

- **競合テストは必須**: 入札・締切・延長に触れるPRは、同時実行のテスト(並列入札、締切とラスト入札の競合)を書かずに完成扱いにしない
- **入札の判定と更新は1文の条件付きUPDATEで行う**: 「読んでから書く」(SELECTで検証→UPDATE)はcheck-then-act競合の温床。
  有効条件(active、締切前、現在価格 + 入札単位以上、出品者・現勝者でない)はUPDATEのWHERE句に押し込む(`.claude/skills/bidding-consistency` 参照)
- **時刻の基準はDB(now())に統一する**: アプリサーバーの時計で締切を判定しない。締切後の入札が1件でも通ったら設計の誤り
- **自動延長は入札と同一のUPDATE文内で行う**: 入札受付と延長の間に締切処理が割り込む隙間を作らない
- ステータス値・テーブル名・エンドポイント名・**WebSocketイベント名**を仕様と1文字も違えない(`price_updated` を `priceUpdate` にしない等)
- カウンタ更新は相対UPDATE(`bids_count = bids_count + 1`)。読み取り→書き戻しはlost updateなので禁止
- エラーレスポンスは常に `{"message": "...", "code": "..."}`(codeの一覧は docs/api.md。`BID_TOO_LOW` 等の大文字スネークケース)
- 金額はすべて整数(円)。浮動小数点を使わない

## 作業の型(スキル)

- 初回オンボーディング: `.claude/skills/project-onboarding/SKILL.md`
- issue着手〜PR: `.claude/skills/issue-workflow/SKILL.md`
- PR前の仕様突合: `.claude/skills/spec-compliance/SKILL.md`
- issue複製セットアップ: `.claude/skills/setup-github-project/SKILL.md`
- 入札整合性・締切競合・WebSocketイベント設計の判断: `.claude/skills/bidding-consistency/SKILL.md`

## 進め方の約束

- M1 → M2 → M3 → M4 の順。1 issue = 1 branch(`feature/<issue番号>-<slug>`)= 1 PR、`Closes #N` を本文に
- PR前に必ず: テスト実行、spec-complianceチェック、セルフレビュー
- 仕様に矛盾を見つけたら勝手に解釈せず、根拠をissueコメントに書いてから docs を修正する
