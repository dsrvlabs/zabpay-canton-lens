#!/usr/bin/env bash
set -euo pipefail

# AWS Secrets Manager 시크릿(JSON 객체) 하나를 받아 docker/.env 로 렌더링한다.
# 값은 파일로만 가고 로그에는 키 개수만 찍는다.
#
# usage: fetch-secrets.sh <secret-id>
#
# 시크릿 형식: {"VITE_AUTH_MODE": "shared-identity", "LEDGER_BASE": "https://...", ...}
#   - 키는 docker/.env.example 의 이름 그대로.
#   - 빈 값("")과 null 은 파일에 쓰지 않는다. compose.yaml 은 SHARED_IDENTITY_* 를
#     "설정돼 있을 때만" 넘기는데, 백엔드는 caller-bearer 모드에서 그 변수가 빈 값으로라도
#     정의돼 있으면 기동을 거부한다. 안 쓰는 키는 시크릿에서 빼거나 비워 두면 된다.
#   - 값은 작은따옴표로 감싸 쓴다. Compose 가 `$` 나 ` #` 를 해석하지 않게 하기 위해서다.
#     그래서 줄바꿈이나 작은따옴표가 든 값은 받지 않는다.
#
# 받기·변환이 전부 끝난 뒤에야 docker/.env 를 바꾼다. 중간에 실패하면 기존 파일이 그대로 남는다.

SECRET_ID="${1:?usage: fetch-secrets.sh <secret-id>}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_FILE="$ROOT/docker/.env"

umask 077
TMP_FILE="$(mktemp "$ROOT/docker/.env.tmp.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --query SecretString \
  --output text \
  | python3 -c '
import json, re, sys

try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit("fetch-secrets: 시크릿이 JSON 이 아니다")
if not isinstance(data, dict):
    sys.exit("fetch-secrets: 시크릿은 JSON 객체여야 한다")

written = 0
for key, value in data.items():
    if not re.fullmatch(r"[A-Z_][A-Z0-9_]*", key):
        sys.exit(f"fetch-secrets: 키 이름이 환경변수 형식이 아니다: {key!r}")
    if value is None or value == "":
        print(f"fetch-secrets: {key} 는 비어 있어 건너뛴다", file=sys.stderr)
        continue
    if isinstance(value, bool):
        value = "true" if value else "false"
    elif isinstance(value, (int, float)):
        value = str(value)
    elif not isinstance(value, str):
        sys.exit(f"fetch-secrets: {key} 의 값이 문자열이 아니다")
    if "\n" in value or "\r" in value or chr(39) in value:
        sys.exit(f"fetch-secrets: {key} 의 값에 줄바꿈이나 작은따옴표가 있어 쓸 수 없다")
    print(f"{key}={chr(39)}{value}{chr(39)}")
    written += 1

if written == 0:
    sys.exit("fetch-secrets: 쓸 키가 하나도 없다")
' > "$TMP_FILE"

mv "$TMP_FILE" "$TARGET_FILE"
echo "fetch-secrets: wrote docker/.env ($(wc -l < "$TARGET_FILE" | tr -d ' ') keys)"
