#!/usr/bin/env bash
# Unix 一键准备开发资源（仓库根目录）
#   ./tools/dev-setup.sh --game-dir "/path/to/Warcraft III"
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec node "$ROOT/tools/dev-setup.mjs" "$@"
