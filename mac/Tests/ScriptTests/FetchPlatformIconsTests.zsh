#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEMPORARY_ROOT="$(mktemp -d "${TMPDIR%/}/zisla-fetch-platform-icons-tests.XXXXXX")"
function cleanup() {
  [[ "$TEMPORARY_ROOT" == "${TMPDIR%/}/zisla-fetch-platform-icons-tests."* ]] || return
  [[ -d "$TEMPORARY_ROOT" ]] && find "$TEMPORARY_ROOT" -depth -delete
}
trap cleanup EXIT

TEST_ROOT="$TEMPORARY_ROOT/project"
FAKE_BIN="$TEMPORARY_ROOT/bin"
DESTINATION="$TEST_ROOT/Resources/BrandIcons"
ORIGINALS="$TEMPORARY_ROOT/originals"
ASSETS=(youtube.svg bilibili.svg xiaohongshu.svg weibo.svg tiktok.svg instagram.svg)

mkdir -p "$TEST_ROOT/Scripts" "$DESTINATION" "$ORIGINALS" "$FAKE_BIN"
cp "$ROOT/Scripts/fetch-platform-icons.sh" "$TEST_ROOT/Scripts/fetch-platform-icons.sh"

for asset in "${ASSETS[@]}"; do
  print -r -- "original-$asset" > "$DESTINATION/$asset"
  cp "$DESTINATION/$asset" "$ORIGINALS/$asset"
done

cat > "$FAKE_BIN/curl" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

output=""
url=""
while (($# > 0)); do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

if [[ "$url" == *"/${FAKE_CURL_FAIL_SLUG:-__never__}.svg" ]]; then
  exit 22
fi

printf '<svg viewBox="0 0 24 24"><path fill="#123456" d="M0 0h24v24H0z"/></svg>\n' > "$output"
SCRIPT
chmod +x "$FAKE_BIN/curl"

tests_run=0

(( tests_run += 1 ))
if output="$(PATH="$FAKE_BIN:$PATH" FAKE_CURL_FAIL_SLUG=tiktok "$TEST_ROOT/Scripts/fetch-platform-icons.sh" 2>&1)"; then
  print -u2 -r -- "FAIL: a partial icon download unexpectedly succeeded"
  exit 1
fi
if ! diff -qr "$ORIGINALS" "$DESTINATION" >/dev/null; then
  print -u2 -r -- "FAIL: a partial icon download changed committed resources"
  diff -ru "$ORIGINALS" "$DESTINATION" >&2 || true
  exit 1
fi

PATH="$FAKE_BIN:$PATH" "$TEST_ROOT/Scripts/fetch-platform-icons.sh" >/dev/null
for asset in "${ASSETS[@]}"; do
  (( tests_run += 1 ))
  if [[ "$(<"$DESTINATION/$asset")" != *'width="24" height="24"'* ]]; then
    print -u2 -r -- "FAIL: $asset is missing its intrinsic dimensions"
    exit 1
  fi
  if [[ "$(<"$DESTINATION/$asset")" != *'fill="#'* ]]; then
    print -u2 -r -- "FAIL: $asset is missing its official brand color"
    exit 1
  fi
  if [[ "$(<"$DESTINATION/$asset")" == *'fill="#123456"'* ]]; then
    print -u2 -r -- "FAIL: $asset retained a child fill that overrides the brand color"
    exit 1
  fi
done

print -r -- "PASS: $tests_run fetch-platform-icons tests"
