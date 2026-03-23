#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_SCRIPT="${HOME}/.codex/skills/vertex-gemini-image/scripts/vertex_gemini_image.py"
REMOVE_BG_SCRIPT="${ROOT_DIR}/scripts/remove_pet_avatar_background.py"
OUTPUT_DIR="${ROOT_DIR}/output/vertex-gemini-image/petpal"
MASTER_DIR="${OUTPUT_DIR}/masters"
PROMPT_DIR="${OUTPUT_DIR}/prompts"
ASSETS_DIR="${ROOT_DIR}/ios/PetPalDemo/Resources/Assets.xcassets"
PYTHON_BIN=""
VERTEX_RETRY_ATTEMPTS="${VERTEX_RETRY_ATTEMPTS:-4}"
VERTEX_RETRY_SLEEP_SECONDS="${VERTEX_RETRY_SLEEP_SECONDS:-20}"
REUSE_EXISTING_MASTER="${REUSE_EXISTING_MASTER:-0}"

if [[ ! -f "${SKILL_SCRIPT}" ]]; then
  echo "Vertex skill 脚本不存在: ${SKILL_SCRIPT}" >&2
  exit 1
fi

if [[ ! -f "${REMOVE_BG_SCRIPT}" ]]; then
  echo "去底脚本不存在: ${REMOVE_BG_SCRIPT}" >&2
  exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "缺少 sips，无法派生 iOS 资源尺寸。" >&2
  exit 1
fi

mkdir -p "${MASTER_DIR}" "${PROMPT_DIR}"

STYLE_PROMPT="PetPal App 静态品牌插画，治愈奶油感，低饱和，圆润二维插画，主体居中，头部和上半身为主，留白充足，轮廓清晰，五官简洁亲和，适合 iOS app icon 和头像，小尺寸下仍清楚。禁止文字、水印、边框、项圈、衣服、玩具、家具、复杂背景、写实摄影、真实毛发细节、3D 渲染、霓虹高饱和配色。最终必须输出 1:1 正方形构图，耳朵完整，不裁切主体。头像资源的背景必须是单一、干净、无纹理的浅奶油色纯底，方便后续自动去底，不能额外再画白色内框、底板、圆角卡片或第二层背景。"

usage() {
  cat <<'EOF'
用法:
  bash scripts/generate_petpal_art.sh [asset...]

可选 asset:
  AppIcon
  ArtPetCat
  ArtPetDog
  ArtPetCatBritish
  ArtPetCatSiamese
  ArtPetCatRagdoll
  ArtPetDogCorgi
  ArtPetDogGolden
  ArtPetDogShiba
  all

示例:
  bash scripts/generate_petpal_art.sh AppIcon
  bash scripts/generate_petpal_art.sh ArtPetCat ArtPetDog
  bash scripts/generate_petpal_art.sh all

可选环境变量:
  PYTHON_BIN_OVERRIDE=/path/to/python
  REUSE_EXISTING_MASTER=1
EOF
}

log() {
  printf '[petpal-art] %s\n' "$*"
}

require_vertex_env() {
  if [[ -z "${GOOGLE_CLOUD_PROJECT:-}" && -z "${VERTEX_AI_PROJECT:-}" ]]; then
    echo "请先设置 GOOGLE_CLOUD_PROJECT 或 VERTEX_AI_PROJECT。" >&2
    exit 1
  fi
}

resolve_python_bin() {
  local candidates=()

  if [[ -n "${PYTHON_BIN_OVERRIDE:-}" ]]; then
    candidates+=("${PYTHON_BIN_OVERRIDE}")
  fi

  if [[ -x "${ROOT_DIR}/backend/.venv/bin/python" ]]; then
    candidates+=("${ROOT_DIR}/backend/.venv/bin/python")
  fi

  candidates+=(python3 python3.13 python3.12 python3.11)

  for candidate in "${candidates[@]}"; do
    if ! command -v "${candidate}" >/dev/null 2>&1; then
      continue
    fi

    if "${candidate}" - <<'PY' >/dev/null 2>&1
from google import genai  # noqa: F401
PY
    then
      PYTHON_BIN="${candidate}"
      return
    fi
  done

  for candidate in "${candidates[@]}"; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      PYTHON_BIN="${candidate}"
      return
    fi
  done

  echo "未找到可用的 Python 解释器。" >&2
  exit 1
}

generate_master() {
  local asset="$1"
  local prompt="$2"
  local prompt_file="${PROMPT_DIR}/${asset}.txt"
  local master_file="${MASTER_DIR}/${asset}.png"
  local attempt=1
  local delay="${VERTEX_RETRY_SLEEP_SECONDS}"

  printf '%s\n' "${prompt}" > "${prompt_file}"

  if [[ "${REUSE_EXISTING_MASTER}" == "1" && -f "${master_file}" ]]; then
    log "复用现有 master 图: ${asset}"
    return
  fi

  while true; do
    log "生成 master 图: ${asset} (attempt ${attempt}/${VERTEX_RETRY_ATTEMPTS})"
    if "${PYTHON_BIN}" "${SKILL_SCRIPT}" \
      --prompt "${prompt}" \
      --aspect-ratio 1:1 \
      --out "${master_file}"; then
      return
    fi

    if (( attempt >= VERTEX_RETRY_ATTEMPTS )); then
      echo "生成失败，已达到最大重试次数: ${asset}" >&2
      exit 1
    fi

    log "生成失败，${delay}s 后重试: ${asset}"
    sleep "${delay}"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

process_avatar_master() {
  local asset="$1"
  local master_file="${MASTER_DIR}/${asset}.png"

  log "去底处理: ${asset}"
  "${PYTHON_BIN}" "${REMOVE_BG_SCRIPT}" \
    --input "${master_file}" \
    --output "${master_file}"
}

resize_square() {
  local source="$1"
  local size="$2"
  local target="$3"
  mkdir -p "$(dirname "${target}")"
  sips -s format png -z "${size}" "${size}" "${source}" --out "${target}" >/dev/null
}

publish_default_asset() {
  local asset="$1"
  local master_file="${MASTER_DIR}/${asset}.png"
  local target_dir="${ASSETS_DIR}/${asset}.imageset"

  if [[ ! -f "${master_file}" ]]; then
    echo "缺少 master 图: ${master_file}" >&2
    exit 1
  fi

  log "派生默认头像尺寸: ${asset}"
  resize_square "${master_file}" 128 "${target_dir}/${asset}-1x.png"
  resize_square "${master_file}" 256 "${target_dir}/${asset}-2x.png"
  resize_square "${master_file}" 384 "${target_dir}/${asset}-3x.png"
}

publish_app_icon() {
  local master_file="${MASTER_DIR}/AppIcon.png"
  local target_dir="${ASSETS_DIR}/AppIcon.appiconset"

  if [[ ! -f "${master_file}" ]]; then
    echo "缺少 master 图: ${master_file}" >&2
    exit 1
  fi

  log "派生 AppIcon 全尺寸"
  while IFS=':' read -r filename size; do
    resize_square "${master_file}" "${size}" "${target_dir}/${filename}"
  done <<'EOF'
AppIcon-iphone-20-2x.png:40
AppIcon-iphone-20-3x.png:60
AppIcon-iphone-29-2x.png:58
AppIcon-iphone-29-3x.png:87
AppIcon-iphone-40-2x.png:80
AppIcon-iphone-40-3x.png:120
AppIcon-iphone-60-2x.png:120
AppIcon-iphone-60-3x.png:180
AppIcon-ipad-20-1x.png:20
AppIcon-ipad-20-2x.png:40
AppIcon-ipad-29-1x.png:29
AppIcon-ipad-29-2x.png:58
AppIcon-ipad-40-1x.png:40
AppIcon-ipad-40-2x.png:80
AppIcon-ipad-76-1x.png:76
AppIcon-ipad-76-2x.png:152
AppIcon-ipad-83_5-2x.png:167
AppIcon-ios-marketing-1024-1x.png:1024
EOF
}

build_prompt() {
  local asset="$1"
  local subject=""

  case "${asset}" in
    AppIcon)
      subject="为 PetPal 设计一个 iOS AppIcon 主视觉：一只银灰奶油色、圆脸短毛的小猫和一只米白焦糖色、垂耳的小狗并置依偎，两个角色都面向前方，彼此贴近，形成单一品牌记忆点。背景统一为柔和暖杏色，不要额外图形元素，不要拟物图标边框。"
      ;;
    ArtPetCat)
      subject="生成 PetPal 的默认猫咪头像，美短气质，银灰白短毛，圆脸，眼神温柔，轻微好奇感，胸像视角。"
      ;;
    ArtPetDog)
      subject="生成 PetPal 的默认狗狗头像，比格气质，奶油白底配焦糖棕斑块，垂耳，表情亲和，胸像视角。"
      ;;
    ArtPetCatBritish)
      subject="生成英短默认头像，圆脸，厚实短毛，蓝灰主色，神态沉静可爱，胸像视角。"
      ;;
    ArtPetCatSiamese)
      subject="生成暹罗猫默认头像，浅奶油色身体，重点色面部和耳朵，脸型更修长，眼神灵动，胸像视角。"
      ;;
    ArtPetCatRagdoll)
      subject="生成布偶猫默认头像，长毛，柔和双色，蓝眼倾向，毛感蓬松但保持简洁，胸像视角。"
      ;;
    ArtPetDogCorgi)
      subject="生成柯基默认头像，橘白配色，立耳，脸颊饱满，通过头脸比例暗示短腿和活泼感，胸像视角。"
      ;;
    ArtPetDogGolden)
      subject="生成金毛默认头像，奶油金长毛，垂耳，笑意温和，亲近感强，胸像视角。"
      ;;
    ArtPetDogShiba)
      subject="生成柴犬默认头像，橘白配色，三角立耳，口鼻区清晰，神态机灵，胸像视角。"
      ;;
    *)
      echo "不支持的 asset: ${asset}" >&2
      exit 1
      ;;
  esac

  printf '%s %s\n' "${STYLE_PROMPT}" "${subject}"
}

render_asset() {
  local asset="$1"
  local prompt
  prompt="$(build_prompt "${asset}")"
  generate_master "${asset}" "${prompt}"

  if [[ "${asset}" == "AppIcon" ]]; then
    publish_app_icon
  else
    process_avatar_master "${asset}"
    publish_default_asset "${asset}"
  fi
}

main() {
  require_vertex_env
  resolve_python_bin
  log "使用 Python: ${PYTHON_BIN}"

  local assets=("$@")
  if [[ ${#assets[@]} -eq 0 ]]; then
    assets=("all")
  fi

  if [[ "${assets[0]}" == "--help" || "${assets[0]}" == "-h" ]]; then
    usage
    exit 0
  fi

  if [[ " ${assets[*]} " == *" all "* ]]; then
    assets=(
      AppIcon
      ArtPetCat
      ArtPetDog
      ArtPetCatBritish
      ArtPetCatSiamese
      ArtPetCatRagdoll
      ArtPetDogCorgi
      ArtPetDogGolden
      ArtPetDogShiba
    )
  fi

  for asset in "${assets[@]}"; do
    render_asset "${asset}"
  done

  log "完成。master 图保存在 ${MASTER_DIR}"
}

main "$@"
