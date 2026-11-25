#!/bin/bash
set -euo pipefail
PORT=$(python3 -c 'import json;print(json.load(open("/home/debianuser/.config/prisir/open_api.json")).get("port",23331))')
echo "PORT=$PORT"
runuser -u debianuser -- curl -s "http://127.0.0.1:$PORT/health"; echo
echo "=== user_add ==="
runuser -u debianuser -- curl -s "http://127.0.0.1:$PORT/rpc" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"user_add","params":{"word":"开放接口探针","pos":1},"id":1}'
echo
echo "=== user_add_batch ==="
runuser -u debianuser -- curl -s "http://127.0.0.1:$PORT/rpc" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"user_add_batch","params":{"words":["fcitx5","灵犀拼音","雅可比猜想"],"pos":1},"id":2}'
echo
echo "=== query lingxipinyin ==="
runuser -u debianuser -- curl -s "http://127.0.0.1:$PORT/rpc" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"query","params":{"pinyin":"lingxipinyin"},"id":3}'
echo
echo "=== query lxpy ==="
runuser -u debianuser -- curl -s "http://127.0.0.1:$PORT/rpc" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"query","params":{"pinyin":"lxpy"},"id":4}'
echo
