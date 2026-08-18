#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  issue)
    section_title="Issue"
    ;;
  pr)
    section_title="Pull Request"
    ;;
  *)
    printf 'Usage: %s <issue|pr>\n' "$0" >&2
    exit 1
    ;;
esac

repository_root="$(git rev-parse --show-toplevel)"
contributing_file="$repository_root/CONTRIBUTING.md"
if [[ ! -f "$contributing_file" ]]; then
  printf 'CONTRIBUTING.md not found at repository root.\n' >&2
  exit 1
fi

section_content="$(awk -v title="## $section_title" '
  $0 == title {
    in_section = 1
    next
  }
  in_section && /^## / {
    exit
  }
  in_section && !has_content && $0 == "" {
    next
  }
  in_section {
    has_content = 1
    print
  }
' "$contributing_file")"

if [[ -z "$section_content" ]]; then
  printf 'Section "## %s" not found in CONTRIBUTING.md.\n' "$section_title" >&2
  exit 1
fi

server_url="${GITHUB_SERVER_URL:-https://github.com}"
repository="${GITHUB_REPOSITORY:-wzz6423/zisla}"
default_branch="${GITHUB_DEFAULT_BRANCH:-main}"
contributing_url="$server_url/$repository/blob/$default_branch/CONTRIBUTING.md"

cat <<EOF
<!-- zisla-contributor-welcome -->
> Automated reply: the following guidance comes from [CONTRIBUTING.md]($contributing_url).

$section_content
EOF
