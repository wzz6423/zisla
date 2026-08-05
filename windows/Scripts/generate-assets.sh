#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
swift "$ROOT/Scripts/generate-assets.swift" "$ROOT/App/Assets"
