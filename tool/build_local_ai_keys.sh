#!/usr/bin/env bash
# 用本机的 ai_keys.local.env 出一个「装好就免填 key」的包。
#
#   ./tool/build_local_ai_keys.sh
#
# ai_keys.local.env 每行一个 KEY=VALUE，只认这五个：
#   BEE_AI_KEY_ZHIPU      智谱GLM
#   BEE_AI_KEY_REQUESTY   Requesty 免费池
#   BEE_AI_KEY_DOTS       小红书点点
#   BEE_AI_KEY_INTERN     书生·端砚
#   BEE_AI_KEY_KILO       Kilo 免费池
# 缺哪个就少注入哪个，其余照常。
#
# 这个文件已在 .gitignore 里，仓库和 GitHub 上的包永远不含 key。
# 但这样构建出来的 APK 里 key 是明文可提取的 —— 只给自己那几台设备装，别外发。
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE=ai_keys.local.env
if [ ! -f "$ENV_FILE" ]; then
  echo "缺少 $ENV_FILE，参照本脚本注释建一个" >&2
  exit 1
fi

read_key() {
  # 只取最后一个同名赋值，顺手吃掉 Windows 的 \r
  tr -d '\r' <"$ENV_FILE" | grep -E "^$1=" | tail -1 | cut -d= -f2- || true
}

DEFINE=()
for pair in "zhipu:BEE_AI_KEY_ZHIPU" "requesty:BEE_AI_KEY_REQUESTY" "dots:BEE_AI_KEY_DOTS" "intern:BEE_AI_KEY_INTERN" "kilo:BEE_AI_KEY_KILO"; do
  name="${pair#*:}"
  value="$(read_key "$name")"
  if [ -n "$value" ]; then
    DEFINE+=("--dart-define=${name}=${value}")
    echo "注入 $name（长度 ${#value}）"
  else
    echo "跳过 $name（未配置）"
  fi
done

if [ ${#DEFINE[@]} -eq 0 ]; then
  echo "$ENV_FILE 里没有任何可用 key" >&2
  exit 1
fi

exec flutter build apk --release --flavor prod --target-platform android-arm64 \
  --split-per-abi "${DEFINE[@]}"
