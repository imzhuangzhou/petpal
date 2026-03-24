#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is not installed or not in PATH." >&2
  exit 1
fi

if [ ! -d ".venv" ]; then
  echo "Creating virtual environment in $SCRIPT_DIR/.venv ..."
  python3 -m venv .venv
fi

# shellcheck disable=SC1091
source ".venv/bin/activate"

REQUIREMENTS_STAMP=".venv/.requirements-installed"
if [ ! -f "$REQUIREMENTS_STAMP" ] || [ "requirements.txt" -nt "$REQUIREMENTS_STAMP" ]; then
  echo "Installing backend dependencies ..."
  python -m pip install -U pip
  python -m pip install -r requirements.txt
  touch "$REQUIREMENTS_STAMP"
fi

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
export VERTEX_IMAGE_MODEL="${VERTEX_IMAGE_MODEL:-gemini-3.1-flash-image-preview}"
export PETPAL_ENABLE_AVATAR_IDENTITY_EXTRACTION="${PETPAL_ENABLE_AVATAR_IDENTITY_EXTRACTION:-true}"

exec python -m uvicorn main:app --reload --host "$HOST" --port "$PORT"
