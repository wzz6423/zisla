#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_OUTPUT="$REPOSITORY_ROOT/mac/Resources/Emoji/EmojiNameAliases.json"
OUTPUT="$DEFAULT_OUTPUT"
CHECK_ONLY=false

usage() {
  cat <<'EOF'
Usage: mac/Scripts/update-emoji-catalog.sh [--check] [--output PATH]

Downloads the latest stable CLDR and CLDR JSON releases, then writes the
fully-qualified Emoji alias catalog. --check leaves the working tree unchanged
and exits nonzero when the generated catalog differs from the selected output.
EOF
}

while (($# > 0)); do
  case "$1" in
    --check)
      CHECK_ONLY=true
      shift
      ;;
    --output)
      if (($# < 2)); then
        echo "error: --output requires a path" >&2
        exit 2
      fi
      OUTPUT="$2"
      shift 2
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      echo "error: unsupported argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$OUTPUT" in
  /*) ;;
  *) OUTPUT="$REPOSITORY_ROOT/$OUTPUT" ;;
esac

temporary_parent="${TMPDIR:-/tmp}"
temporary_parent="${temporary_parent%/}"
TEMPORARY_ROOT="$(mktemp -d "$temporary_parent/zisla-emoji-catalog.XXXXXX")"
TEMPORARY_OUTPUT=""

cleanup() {
  if [[ -n "$TEMPORARY_OUTPUT" && -f "$TEMPORARY_OUTPUT" ]]; then
    rm -f "$TEMPORARY_OUTPUT"
  fi
  if [[ -d "$TEMPORARY_ROOT" && "$TEMPORARY_ROOT" == "$temporary_parent"/zisla-emoji-catalog.* ]]; then
    find "$TEMPORARY_ROOT" -depth -delete
  fi
}
trap cleanup EXIT

curl_arguments=(
  --fail
  --location
  --silent
  --show-error
  --retry 3
  --retry-all-errors
  --connect-timeout 20
  --max-time 120
  --header "Accept: application/vnd.github+json"
  --header "X-GitHub-Api-Version: 2022-11-28"
  --header "User-Agent: zisla-emoji-catalog-updater"
)
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  curl_arguments+=(--header "Authorization: Bearer $GITHUB_TOKEN")
fi

use_gh_api=false
if [[ -z "${GITHUB_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  use_gh_api=true
fi

fetch_api() {
  local url="$1"
  local destination="$2"
  if "$use_gh_api"; then
    gh api --method GET "$url" > "$destination"
  else
    curl "${curl_arguments[@]}" "$url" -o "$destination"
  fi
}

API_ROOT="https://api.github.com/repos/unicode-org"
fetch_api "$API_ROOT/cldr/releases/latest" "$TEMPORARY_ROOT/cldr-release.json"
fetch_api "$API_ROOT/cldr-json/releases/latest" "$TEMPORARY_ROOT/cldr-json-release.json"

python3 - \
  "$TEMPORARY_ROOT/cldr-release.json" \
  "$TEMPORARY_ROOT/cldr-json-release.json" \
  "$TEMPORARY_ROOT/release-metadata.json" <<'PY'
import json
import re
import sys


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def fail(message):
    raise SystemExit(f"error: {message}")


cldr_release = load(sys.argv[1])
cldr_json_release = load(sys.argv[2])

for release, repository in ((cldr_release, "unicode-org/cldr"), (cldr_json_release, "unicode-org/cldr-json")):
    if release.get("draft") or release.get("prerelease"):
        fail(f"{repository} latest release is not a stable published release")

cldr_tag = str(cldr_release.get("tag_name", ""))
cldr_json_tag = str(cldr_json_release.get("tag_name", ""))
cldr_match = re.fullmatch(r"release-(\d+)(?:-(\d+))?", cldr_tag)
json_match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", cldr_json_tag)
if not cldr_match:
    fail(f"unsupported unicode-org/cldr release tag: {cldr_tag!r}")
if not json_match:
    fail(f"unsupported unicode-org/cldr-json release tag: {cldr_json_tag!r}")

cldr_major = int(cldr_match.group(1))
cldr_patch = int(cldr_match.group(2) or 0)
json_major, json_minor, _ = map(int, json_match.groups())
if (cldr_major, cldr_patch) != (json_major, json_minor):
    fail(
        "latest CLDR and CLDR JSON releases do not describe the same data version: "
        f"{cldr_tag} versus {cldr_json_tag}"
    )

with open(sys.argv[3], "w", encoding="utf-8") as handle:
    json.dump(
        {
            "cldrJsonTag": cldr_json_tag,
            "cldrTag": cldr_tag,
            "cldrVersion": f"{cldr_major}.{cldr_patch}",
        },
        handle,
        sort_keys=True,
    )
PY

CLDR_TAG="$(python3 - "$TEMPORARY_ROOT/release-metadata.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["cldrTag"])
PY
)"
CLDR_JSON_TAG="$(python3 - "$TEMPORARY_ROOT/release-metadata.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["cldrJsonTag"])
PY
)"

fetch_api "$API_ROOT/cldr/commits/$CLDR_TAG" "$TEMPORARY_ROOT/cldr-commit.json"
fetch_api "$API_ROOT/cldr-json/commits/$CLDR_JSON_TAG" "$TEMPORARY_ROOT/cldr-json-commit.json"

python3 - \
  "$TEMPORARY_ROOT/release-metadata.json" \
  "$TEMPORARY_ROOT/cldr-commit.json" \
  "$TEMPORARY_ROOT/cldr-json-commit.json" <<'PY'
import json
import re
import sys


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


metadata = load(sys.argv[1])
for path, key in ((sys.argv[2], "cldrCommit"), (sys.argv[3], "cldrJsonCommit")):
    revision = str(load(path).get("sha", ""))
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise SystemExit(f"error: {key} is not a full Git revision")
    metadata[key] = revision

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(metadata, handle, sort_keys=True)
PY

CLDR_COMMIT="$(python3 - "$TEMPORARY_ROOT/release-metadata.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["cldrCommit"])
PY
)"
CLDR_JSON_COMMIT="$(python3 - "$TEMPORARY_ROOT/release-metadata.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["cldrJsonCommit"])
PY
)"

EMOJI_TEST_PATH="tools/cldr-code/src/main/resources/org/unicode/cldr/util/data/emoji/emoji-test.txt"
fetch_api \
  "$API_ROOT/cldr/contents/$EMOJI_TEST_PATH?ref=$CLDR_COMMIT" \
  "$TEMPORARY_ROOT/emoji-test.content.json"

LANGUAGE_SOURCES=(
  "ar:ar"
  "de:de"
  "en:en"
  "es:es"
  "fr:fr"
  "id:id"
  "it:it"
  "ja:ja"
  "ko:ko"
  "nl:nl"
  "pt-BR:pt"
  "ru:ru"
  "th:th"
  "tr:tr"
  "vi:vi"
  "zh-Hans:zh"
  "zh-Hant:zh-Hant"
)
printf '%s\n' "${LANGUAGE_SOURCES[@]}" > "$TEMPORARY_ROOT/languages.txt"

for mapping in "${LANGUAGE_SOURCES[@]}"; do
  language="${mapping%%:*}"
  source_language="${mapping#*:}"
  fetch_api \
    "$API_ROOT/cldr-json/contents/cldr-json/cldr-annotations-full/annotations/$source_language/annotations.json?ref=$CLDR_JSON_COMMIT" \
    "$TEMPORARY_ROOT/$language.base.content.json"
  fetch_api \
    "$API_ROOT/cldr-json/contents/cldr-json/cldr-annotations-derived-full/annotationsDerived/$source_language/annotations.json?ref=$CLDR_JSON_COMMIT" \
    "$TEMPORARY_ROOT/$language.derived.content.json"
done

GENERATED_OUTPUT="$TEMPORARY_ROOT/EmojiNameAliases.json"
python3 - \
  "$TEMPORARY_ROOT/release-metadata.json" \
  "$TEMPORARY_ROOT/emoji-test.content.json" \
  "$TEMPORARY_ROOT/languages.txt" \
  "$TEMPORARY_ROOT" \
  "$GENERATED_OUTPUT" <<'PY'
import base64
import json
import re
import sys
from pathlib import Path


EMOJI_TEST_PATH = "tools/cldr-code/src/main/resources/org/unicode/cldr/util/data/emoji/emoji-test.txt"
VARIATION_SELECTORS = {"\ufe0e", "\ufe0f"}


def fail(message):
    raise SystemExit(f"error: {message}")


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def decode_content(path):
    payload = load_json(path)
    if payload.get("encoding") != "base64" or not isinstance(payload.get("content"), str):
        fail(f"GitHub did not return base64 file content for {path}")
    try:
        return base64.b64decode(payload["content"], validate=False).decode("utf-8")
    except (UnicodeDecodeError, ValueError) as error:
        fail(f"cannot decode {path}: {error}")


def presentation_key(emoji):
    return "".join(character for character in emoji if character not in VARIATION_SELECTORS)


def append_unique(target, values):
    seen = set(target)
    for value in values:
        if not isinstance(value, str):
            continue
        value = value.strip()
        if value and value not in seen:
            target.append(value)
            seen.add(value)


def aliases_for(record):
    if not isinstance(record, dict):
        return []
    aliases = []
    for field in ("tts", "default"):
        values = record.get(field, [])
        if isinstance(values, str):
            values = [values]
        if isinstance(values, list):
            append_unique(aliases, values)
    return aliases


def canonical_names_for(record):
    if not isinstance(record, dict):
        return []
    values = record.get("tts", [])
    if isinstance(values, str):
        values = [values]
    names = []
    if isinstance(values, list):
        append_unique(names, values)
    return names


def annotation_records(document, root_key):
    try:
        records = document[root_key]["annotations"]
    except (KeyError, TypeError) as error:
        fail(f"missing {root_key}.annotations: {error}")
    if not isinstance(records, dict):
        fail(f"{root_key}.annotations is not an object")
    return records


def parse_roster(emoji_test):
    version_match = re.search(r"^# Version:\s*(\S+)", emoji_test, re.MULTILINE)
    if not version_match:
        fail("emoji-test.txt does not declare an Emoji version")
    roster = []
    seen = set()
    for line in emoji_test.splitlines():
        match = re.match(r"^([0-9A-F ]+)\s*;\s*fully-qualified\s*#", line)
        if not match:
            continue
        emoji = "".join(chr(int(code_point, 16)) for code_point in match.group(1).split())
        if emoji in seen:
            fail(f"emoji-test.txt repeats a fully-qualified Emoji: {emoji!r}")
        roster.append(emoji)
        seen.add(emoji)
    if not roster:
        fail("emoji-test.txt has no fully-qualified Emoji")
    return version_match.group(1), roster


metadata = load_json(sys.argv[1])
emoji_test_payload = load_json(sys.argv[2])
emoji_test = decode_content(sys.argv[2])
languages_file = Path(sys.argv[3])
temporary_root = Path(sys.argv[4])
output_path = Path(sys.argv[5])
emoji_version, roster = parse_roster(emoji_test)

language_sources = []
for line in languages_file.read_text(encoding="utf-8").splitlines():
    app_language, source_language = line.split(":", 1)
    language_sources.append((app_language, source_language))

aliases_by_language = {}
canonical_names_by_language = {}
for app_language, _ in language_sources:
    aliases_by_key = {}
    canonical_names_by_key = {}
    for suffix, root_key in (("base", "annotations"), ("derived", "annotationsDerived")):
        document = json.loads(decode_content(temporary_root / f"{app_language}.{suffix}.content.json"))
        for emoji, record in annotation_records(document, root_key).items():
            key = presentation_key(emoji)
            aliases = aliases_by_key.setdefault(key, [])
            append_unique(aliases, aliases_for(record))
            names = canonical_names_by_key.setdefault(key, [])
            append_unique(names, canonical_names_for(record))
    aliases_by_language[app_language] = aliases_by_key
    canonical_names_by_language[app_language] = canonical_names_by_key

english_aliases = aliases_by_language.get("en")
english_canonical_names = canonical_names_by_language.get("en")
if english_aliases is None or english_canonical_names is None:
    fail("English annotations are required for deterministic fallback")

languages = {}
canonical_names = {}
fallback_count = 0
canonical_fallback_count = 0
for app_language, _ in language_sources:
    aliases_by_key = aliases_by_language[app_language]
    names_by_key = canonical_names_by_language[app_language]
    output_aliases = {}
    output_canonical_names = {}
    missing = []
    missing_canonical_names = []
    for emoji in roster:
        aliases = aliases_by_key.get(presentation_key(emoji), [])
        if not aliases and app_language != "en":
            aliases = english_aliases.get(presentation_key(emoji), [])
            if aliases:
                fallback_count += 1
        if not aliases:
            missing.append(emoji)
            continue
        output_aliases[emoji] = aliases
        names = names_by_key.get(presentation_key(emoji), [])
        if not names and app_language != "en":
            names = english_canonical_names.get(presentation_key(emoji), [])
            if names:
                canonical_fallback_count += 1
        if not names:
            missing_canonical_names.append(emoji)
            continue
        output_canonical_names[emoji] = names
    if missing:
        sample = ", ".join(missing[:8])
        fail(f"{app_language} has {len(missing)} fully-qualified Emoji without aliases: {sample}")
    if missing_canonical_names:
        sample = ", ".join(missing_canonical_names[:8])
        fail(f"{app_language} has {len(missing_canonical_names)} fully-qualified Emoji without canonical names: {sample}")
    languages[app_language] = output_aliases
    canonical_names[app_language] = output_canonical_names

emoji_test_revision = emoji_test_payload.get("sha")
if not isinstance(emoji_test_revision, str) or not re.fullmatch(r"[0-9a-f]{40}", emoji_test_revision):
    fail("emoji-test.txt source is missing its Git blob revision")

catalog = {
    "cldrRevision": metadata["cldrJsonCommit"],
    "cldrVersion": metadata["cldrVersion"],
    "emojiTestRevision": emoji_test_revision,
    "emojiVersion": emoji_version,
    "fallbackLanguage": "en",
    "canonicalNames": canonical_names,
    "languages": languages,
    "sources": {
        "annotations": "https://github.com/unicode-org/cldr-json/tree/"
        f"{metadata['cldrJsonCommit']}/cldr-json",
        "emojiTest": "https://github.com/unicode-org/cldr/blob/"
        f"{metadata['cldrCommit']}/{EMOJI_TEST_PATH}",
    },
}
with output_path.open("w", encoding="utf-8") as handle:
    json.dump(catalog, handle, ensure_ascii=False, indent=2, sort_keys=True)
    handle.write("\n")

print(
    f"Generated {len(roster)} Emoji entries across {len(languages)} languages "
    f"(Emoji {emoji_version}; CLDR {metadata['cldrVersion']}; "
    f"{fallback_count} alias and {canonical_fallback_count} canonical English fallbacks)."
)
PY

if "$CHECK_ONLY"; then
  if [[ -f "$OUTPUT" ]] && cmp -s "$GENERATED_OUTPUT" "$OUTPUT"; then
    echo "Emoji catalog is up to date: $OUTPUT"
    exit 0
  fi
  echo "Emoji catalog differs from the generated stable CLDR data: $OUTPUT" >&2
  exit 1
fi

OUTPUT_DIRECTORY="$(dirname "$OUTPUT")"
mkdir -p "$OUTPUT_DIRECTORY"
TEMPORARY_OUTPUT="$(mktemp "$OUTPUT_DIRECTORY/.EmojiNameAliases.json.XXXXXX")"
install -m 0644 "$GENERATED_OUTPUT" "$TEMPORARY_OUTPUT"
mv -f "$TEMPORARY_OUTPUT" "$OUTPUT"
TEMPORARY_OUTPUT=""
echo "Emoji catalog updated: $OUTPUT"
