#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="${CPA_CONFIG_PATH:-$ROOT_DIR/config.yaml}"
BINARY_FILE="$ROOT_DIR/cli-proxy-api"
PID_FILE="$ROOT_DIR/cliproxyapi.pid"
LOG_FILE="$ROOT_DIR/cliproxyapi.log"

use_docker() {
  command -v go >/dev/null 2>&1 || return 0
  return 1
}

start_native() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "配置文件不存在: $CONFIG_FILE"
    exit 1
  fi

  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE")"
    if ps -p "$pid" >/dev/null 2>&1; then
      echo "CLIProxyAPI 已在运行，PID=$pid"
      exit 0
    fi
    rm -f "$PID_FILE"
  fi

  echo "编译 CLIProxyAPI..."
  (cd "$ROOT_DIR" && go build -o "$BINARY_FILE" ./cmd/server)

  echo "后台启动 CLIProxyAPI..."
  nohup "$BINARY_FILE" -config "$CONFIG_FILE" >"$LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"

  sleep 2
  if ps -p "$pid" >/dev/null 2>&1; then
    echo "启动成功: PID=$pid"
    echo "Base URL: http://127.0.0.1:8317"
    echo "日志文件: $LOG_FILE"
  else
    echo "启动失败，请检查日志: $LOG_FILE"
    exit 1
  fi
}

stop_native() {
  if [ ! -f "$PID_FILE" ]; then
    echo "未检测到 PID 文件，服务可能未运行"
    exit 0
  fi

  local pid
  pid="$(cat "$PID_FILE")"
  if ps -p "$pid" >/dev/null 2>&1; then
    kill "$pid"
    sleep 1
    if ps -p "$pid" >/dev/null 2>&1; then
      kill -9 "$pid"
    fi
    echo "已停止 CLIProxyAPI，PID=$pid"
  else
    echo "进程不存在，清理 PID 文件"
  fi
  rm -f "$PID_FILE"
}

status_native() {
  if [ ! -f "$PID_FILE" ]; then
    echo "CLIProxyAPI 未运行"
    exit 1
  fi

  local pid
  pid="$(cat "$PID_FILE")"
  if ps -p "$pid" >/dev/null 2>&1; then
    echo "CLIProxyAPI 运行中，PID=$pid"
    exit 0
  fi

  echo "PID 文件存在但进程不存在"
  exit 1
}

logs_native() {
  if [ ! -f "$LOG_FILE" ]; then
    echo "日志文件不存在: $LOG_FILE"
    exit 1
  fi
  tail -n 120 -f "$LOG_FILE"
}

start_docker() {
  echo "未检测到 go，使用 Docker Compose 启动"
  (cd "$ROOT_DIR" && docker compose up -d)
}

stop_docker() {
  (cd "$ROOT_DIR" && docker compose down)
}

status_docker() {
  (cd "$ROOT_DIR" && docker compose ps)
}

logs_docker() {
  (cd "$ROOT_DIR" && docker compose logs -f --tail=120)
}

case "${1:-}" in
  start)
    if use_docker; then start_docker; else start_native; fi
    ;;
  stop)
    if use_docker; then stop_docker; else stop_native; fi
    ;;
  restart)
    if use_docker; then stop_docker || true; start_docker; else stop_native || true; start_native; fi
    ;;
  status)
    if use_docker; then status_docker; else status_native; fi
    ;;
  logs)
    if use_docker; then logs_docker; else logs_native; fi
    ;;
  *)
    echo "用法: $0 {start|stop|restart|status|logs}"
    exit 1
    ;;
esac
