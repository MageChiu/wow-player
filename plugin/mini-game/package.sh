#!/usr/bin/env bash
#
# Sudoku 插件打包脚本
#
# 产出可直接安装/发布的 zip：解压后为顶层 Sudoku/ 目录，放进
# Interface/AddOns/ 即可使用。
#
# 用法:
#   ./package.sh              # 打包到 plugin/dist/Sudoku-<version>.zip
#   ./package.sh --check      # 只做校验，不打包
#   ./package.sh --output DIR # 指定输出目录
#
# 校验项:
#   1. Sudoku.toc 存在且含 ## Version / ## Interface
#   2. Constants.lua 的 C.VERSION 与 .toc 的 Version 一致
#   3. .toc 引用的每个文件都真实存在
#   4. Sudoku/ 下的 .lua 是否有未被 .toc 引用（仅警告）

set -euo pipefail

# --- 路径解析：脚本所在目录即 plugin/mini-game ---------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_NAME="Sudoku"
ADDON_DIR="${SCRIPT_DIR}/${ADDON_NAME}"
TOC_FILE="${ADDON_DIR}/${ADDON_NAME}.toc"
CONSTANTS_FILE="${ADDON_DIR}/Constants.lua"

CHECK_ONLY=0
# 统一插件产出目录：plugin/dist（mini-game 的上一级）。
OUTPUT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

fail() { red "错误: $*"; exit 1; }

# --- 基本存在性检查 ----------------------------------------------------------
[[ -d "$ADDON_DIR" ]]   || fail "找不到插件目录: $ADDON_DIR"
[[ -f "$TOC_FILE" ]]    || fail "找不到 TOC 文件: $TOC_FILE"

# --- 读取 .toc 版本与 Interface ----------------------------------------------
TOC_VERSION="$(grep -i '^## Version:' "$TOC_FILE" | head -n1 | sed 's/^## *[Vv]ersion: *//' | tr -d '\r' | xargs || true)"
TOC_INTERFACE="$(grep -i '^## Interface:' "$TOC_FILE" | head -n1 | sed 's/^## *[Ii]nterface: *//' | tr -d '\r' | xargs || true)"

[[ -n "$TOC_VERSION" ]]   || fail "Sudoku.toc 缺少 ## Version:"
[[ -n "$TOC_INTERFACE" ]] || fail "Sudoku.toc 缺少 ## Interface:"

echo "插件:     $ADDON_NAME"
echo "版本:     $TOC_VERSION"
echo "Interface: $TOC_INTERFACE"

# --- 校验 Constants.lua 版本一致 ---------------------------------------------
if [[ -f "$CONSTANTS_FILE" ]]; then
  CONST_VERSION="$(grep -E 'C\.VERSION' "$CONSTANTS_FILE" | head -n1 | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '\r' | xargs || true)"
  if [[ -n "$CONST_VERSION" && "$CONST_VERSION" != "$TOC_VERSION" ]]; then
    fail "版本不一致: Sudoku.toc=$TOC_VERSION, Constants.lua=$CONST_VERSION"
  fi
  green "版本一致校验通过 (Constants.lua = $CONST_VERSION)"
fi

# --- 校验 .toc 引用的文件都存在 ----------------------------------------------
MISSING=0
REFERENCED=()
while IFS= read -r line; do
  line="$(printf '%s' "$line" | tr -d '\r')"       # 去回车
  line="${line#"${line%%[![:space:]]*}"}"          # 去前导空白
  line="${line%"${line##*[![:space:]]}"}"          # 去尾随空白
  [[ -z "$line" ]] && continue                      # 空行
  [[ "$line" == \#* ]] && continue                  # 注释/元数据
  rel_path="${line//\\//}"                          # 反斜杠转正斜杠
  REFERENCED+=("$rel_path")
  if [[ ! -f "${ADDON_DIR}/${rel_path}" ]]; then
    red "  缺失文件: $rel_path"
    MISSING=$((MISSING + 1))
  fi
done < "$TOC_FILE"

[[ "$MISSING" -eq 0 ]] || fail "$MISSING 个 .toc 引用的文件不存在"
green ".toc 引用文件校验通过 (${#REFERENCED[@]} 个文件)"

# --- 警告未被 .toc 引用的 .lua -----------------------------------------------
while IFS= read -r luafile; do
  rel="${luafile#"$ADDON_DIR"/}"
  found=0
  for ref in "${REFERENCED[@]}"; do
    [[ "$ref" == "$rel" ]] && { found=1; break; }
  done
  [[ "$found" -eq 0 ]] && yellow "  警告: $rel 未被 .toc 引用（不会被游戏加载）"
done < <(find "$ADDON_DIR" -name '*.lua' -type f)

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  green "校验完成（--check，未打包）。"
  exit 0
fi

# --- 打包 --------------------------------------------------------------------
command -v zip >/dev/null 2>&1 || fail "未找到 zip 命令，请先安装 zip"

mkdir -p "$OUTPUT_DIR"
ZIP_NAME="${ADDON_NAME}-${TOC_VERSION}.zip"
ZIP_PATH="${OUTPUT_DIR}/${ZIP_NAME}"
rm -f "$ZIP_PATH"

# 在本目录内打包，使 zip 顶层为 Sudoku/；排除系统与开发垃圾文件。
(
  cd "$SCRIPT_DIR"
  zip -r -q -X "$ZIP_PATH" "$ADDON_NAME" \
    -x '*.DS_Store' \
    -x '__MACOSX/*' \
    -x '*/.git/*' \
    -x '*.swp' \
    -x '*.bak' \
    -x '*/.pkgmeta'
)

green "打包完成: $ZIP_PATH"
echo "内容预览:"
unzip -l "$ZIP_PATH" | sed 's/^/  /'
