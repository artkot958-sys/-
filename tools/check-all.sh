#!/usr/bin/env bash
# Запускает все проверки проекта
set -e
cd "$(dirname "$0")/.."
echo "=== 1/3 СИНТАКСИС ==="
node tools/check-syntax.js
echo
echo "=== 2/3 СВОЙСТВА ROBLOX ==="
node tools/check-properties.js
echo
echo "=== 3/3 НЕОПРЕДЕЛЁННЫЕ ИМЕНА ==="
node tools/check-globals.js
echo
echo "=== ПОРЯДОК ОБЪЯВЛЕНИЙ ==="
node tools/check-order.js
