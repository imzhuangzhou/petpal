#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_PORT="${FRONTEND_PORT:-5173}"

BACKEND_PID=""
FRONTEND_PID=""

cleanup() {
  local exit_code=$?

  if [[ -n "$BACKEND_PID" ]] && kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
    kill "$BACKEND_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$FRONTEND_PID" ]] && kill -0 "$FRONTEND_PID" >/dev/null 2>&1; then
    kill "$FRONTEND_PID" >/dev/null 2>&1 || true
  fi

  exit "$exit_code"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令：$1"
    exit 1
  fi
}

check_port() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "端口 $port 已被占用，请先关闭对应进程后再启动。"
    exit 1
  fi
}

trap cleanup EXIT INT TERM

require_command python3
require_command npm

check_port "$BACKEND_PORT"
check_port "$FRONTEND_PORT"

if [[ ! -d "$BACKEND_DIR/.venv" ]]; then
  echo "==> 创建后端虚拟环境"
  python3 -m venv "$BACKEND_DIR/.venv"
fi

if [[ ! -x "$BACKEND_DIR/.venv/bin/python" ]]; then
  echo "后端虚拟环境不完整，请删除 backend/.venv 后重试。"
  exit 1
fi

if [[ ! -d "$FRONTEND_DIR/node_modules" ]]; then
  echo "==> 安装前端依赖"
  (cd "$FRONTEND_DIR" && npm install)
fi

if [[ ! -f "$BACKEND_DIR/.venv/.deps-installed" ]]; then
  echo "==> 安装后端依赖"
  (
    cd "$BACKEND_DIR"
    "$BACKEND_DIR/.venv/bin/python" -m pip install -r requirements.txt
    touch "$BACKEND_DIR/.venv/.deps-installed"
  )
fi

echo "==> 启动 PetPal"
if [[ -z "${DASHSCOPE_API_KEY:-}" ]]; then
  echo "提示：当前未设置 DASHSCOPE_API_KEY。界面能打开，但聊天/日报/日记等模型能力会失败。"
fi

(
  cd "$BACKEND_DIR"
  exec "$BACKEND_DIR/.venv/bin/python" -m uvicorn main:app --reload --host 0.0.0.0 --port "$BACKEND_PORT"
) &
BACKEND_PID=$!

(
  cd "$FRONTEND_DIR"
  exec npm run dev -- --host 0.0.0.0 --port "$FRONTEND_PORT"
) &
FRONTEND_PID=$!

echo
echo "前端地址: http://localhost:$FRONTEND_PORT"
echo "后端地址: http://localhost:$BACKEND_PORT"
echo "按 Ctrl+C 可以一起关闭前后端"
echo

wait "$BACKEND_PID" "$FRONTEND_PID"
