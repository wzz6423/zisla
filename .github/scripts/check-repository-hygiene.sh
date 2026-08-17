#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "$repository_root"

violations=0

report_violation() {
  local reason="$1"
  local path="$2"

  printf 'Forbidden %s: %s\n' "$reason" "$path" >&2
  violations=$((violations + 1))
}

is_allowed_binary_path() {
  case "$1" in
    mac/Resources/MediaRemoteAdapter.framework | mac/Resources/MediaRemoteAdapter.framework/* | mac/Vendor/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

while IFS= read -r -d '' entry; do
  metadata="${entry%%$'\t'*}"
  path="${entry#*$'\t'}"
  mode="${metadata%% *}"

  case "$path" in
    VOICE_INPUT_FIX*.md | */VOICE_INPUT_FIX*.md)
      report_violation "temporary voice-input report" "$path"
      continue
      ;;
    reports | reports/* | */reports | */reports/* | Reports | Reports/* | */Reports | */Reports/*)
      report_violation "report path" "$path"
      continue
      ;;
    .impeccable | .impeccable/* | */.impeccable | */.impeccable/*)
      report_violation ".impeccable path" "$path"
      continue
      ;;
    mac/.build | mac/.build/* | mac/dist | mac/dist/*)
      report_violation "macOS build output" "$path"
      continue
      ;;
    .DS_Store | */.DS_Store)
      report_violation "macOS metadata file" "$path"
      continue
      ;;
  esac

  if is_allowed_binary_path "$path"; then
    continue
  fi

  case "$path" in
    .build | .build/* | */.build | */.build/* | \
      dist | dist/* | */dist | */dist/* | \
      DerivedData | DerivedData/* | */DerivedData | */DerivedData/* | \
      windows/[Bb]in | windows/[Bb]in/* | windows/[Oo]bj | windows/[Oo]bj/* | \
      windows/.vs | windows/.vs/*)
      report_violation "build output path" "$path"
      continue
      ;;
    *.o | *.obj | *.a | *.dylib | *.so | *.dll | *.exe | *.pdb | \
      *.dmg | *.pkg | *.zip | \
      *.app | *.app/* | *.dSYM | *.dSYM/* | \
      *.framework | *.framework/* | *.xcframework | *.xcframework/* | \
      *.xcarchive | *.xcarchive/* | *.xcresult | *.xcresult/* | \
      *.gcda | *.gcno | *.gcov | *.profdata | *.profraw | \
      *.swiftdoc | *.swiftmodule | *.swiftsourceinfo)
      report_violation "generated build artifact" "$path"
      continue
      ;;
  esac

  if [[ "$mode" == "100755" && -f "$path" ]]; then
    mime_type="$(file -b --mime-type -- "$path")"
    mime_type="${mime_type%%$'\n'*}"
    case "$mime_type" in
      application/x-dosexec | application/x-executable | application/x-mach-binary | \
        application/x-pie-executable | application/x-sharedlib | \
        application/vnd.microsoft.portable-executable)
        report_violation "compiled executable" "$path"
        ;;
    esac
  fi
done < <(git ls-files --stage -z)

if ((violations > 0)); then
  printf 'Repository hygiene check failed with %d violation(s).\n' "$violations" >&2
  exit 1
fi

printf 'Repository hygiene check passed.\n'
