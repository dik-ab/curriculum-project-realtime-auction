#!/usr/bin/env bash
#
# setup_issues.sh — 受講者自身のリポジトリにラベル・マイルストーン・issueを複製します。
#
# 使い方:
#   ./scripts/setup_issues.sh                # カレントディレクトリのリポジトリに複製
#   ./scripts/setup_issues.sh owner/repo     # リポジトリを明示指定
#
# 冪等です: ラベルは上書き(--force)、マイルストーン・issueは同名(同タイトル)が
# 存在すればスキップするので、途中で失敗しても再実行できます。
# advanced 2件(ADV-01 / ADV-02)はマイルストーンなしで作成されます。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISSUES_JSON="${SCRIPT_DIR}/issues.json"
TEMPLATE_REPO="dik-ab/curriculum-project-realtime-auction"

# ---- 前提チェック ----------------------------------------------------------
for cmd in gh jq; do
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "ERROR: ${cmd} が見つかりません。インストールしてください。" >&2
    exit 1
  fi
done

if ! gh auth status > /dev/null 2>&1; then
  echo "ERROR: GitHub CLI が未認証です。'gh auth login' を実行してください。" >&2
  exit 1
fi

if [[ ! -f "$ISSUES_JSON" ]]; then
  echo "ERROR: ${ISSUES_JSON} が見つかりません。" >&2
  exit 1
fi

# ---- 対象リポジトリ($1 省略時はカレントのリポジトリ)-----------------------
if [[ $# -ge 1 ]]; then
  REPO="$1"
else
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

if [[ "$REPO" == "$TEMPLATE_REPO" ]]; then
  echo "ERROR: テンプレート元リポジトリ(${TEMPLATE_REPO})には複製できません。" >&2
  echo "       Use this template から作成した自分のリポジトリを指定してください。" >&2
  exit 1
fi
echo "==> 対象リポジトリ: ${REPO}"

# ---- ラベル(--force で冪等に上書き)---------------------------------------
echo "==> ラベルを作成します"
jq -c '.labels[]' "$ISSUES_JSON" | while read -r label; do
  name="$(jq -r '.name' <<< "$label")"
  color="$(jq -r '.color' <<< "$label")"
  desc="$(jq -r '.description' <<< "$label")"
  gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force
  echo "    label: ${name}"
done

# ---- マイルストーン(同名が存在すればスキップ)-----------------------------
echo "==> マイルストーンを作成します"
existing_milestones="$(gh api "repos/${REPO}/milestones?state=all&per_page=100" -q '.[].title')"
jq -c '.milestones[]' "$ISSUES_JSON" | while read -r ms; do
  title="$(jq -r '.title' <<< "$ms")"
  desc="$(jq -r '.description' <<< "$ms")"
  if grep -Fxq "$title" <<< "$existing_milestones"; then
    echo "    skip(既存): ${title}"
  else
    gh api "repos/${REPO}/milestones" -f title="$title" -f description="$desc" > /dev/null
    echo "    milestone: ${title}"
  fi
done

# ---- issue(同タイトルが存在すればスキップ)--------------------------------
echo "==> issueを作成します"
existing_issues="$(gh issue list --repo "$REPO" --state all --limit 500 --json title -q '.[].title')"
total="$(jq '.issues | length' "$ISSUES_JSON")"
created=0
skipped=0
for i in $(seq 0 $((total - 1))); do
  issue="$(jq -c ".issues[$i]" "$ISSUES_JSON")"
  title="$(jq -r '.title' <<< "$issue")"
  if grep -Fxq "$title" <<< "$existing_issues"; then
    echo "    skip(既存): ${title}"
    skipped=$((skipped + 1))
    continue
  fi
  milestone="$(jq -r '.milestone // empty' <<< "$issue")"
  labels="$(jq -r '.labels | join(",")' <<< "$issue")"
  body_file="$(mktemp)"
  jq -r '.body' <<< "$issue" > "$body_file"
  if [[ -n "$milestone" ]]; then
    gh issue create --repo "$REPO" \
      --title "$title" \
      --body-file "$body_file" \
      --label "$labels" \
      --milestone "$milestone" > /dev/null
  else
    gh issue create --repo "$REPO" \
      --title "$title" \
      --body-file "$body_file" \
      --label "$labels" > /dev/null
  fi
  rm -f "$body_file"
  echo "    issue: ${title}"
  created=$((created + 1))
done

echo "==> 完了: issue ${created}件作成 / ${skipped}件スキップ(全${total}件)"
echo "    確認: gh issue list --repo ${REPO} --limit 30"
