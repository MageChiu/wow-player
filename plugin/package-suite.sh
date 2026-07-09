#!/usr/bin/env bash
#
# WowPlayerSuite 整合包（Bundle）总打包脚本
#
# 把 Hub 与各子插件汇集进一个 zip：解压后为并列的多个插件文件夹，
# 一次拖进 Interface/AddOns/ 即全部装齐。
#
#   解压 WowPlayerSuite-Bundle-<套件版本>.zip:
#     ├── WowPlayerSuite/
#     ├── MyChat/
#     ├── RoleManager/
#     ├── CombatCoach/
#     └── QuickDisenchant/
#
# 与各插件自己的 package.sh 并存：想要整合体验下这个 bundle；只想要单个
# 插件仍可下对应的单独 zip。
#
# 用法:
#   ./package-suite.sh              # 打包到 plugin/dist/WowPlayerSuite-Bundle-<版本>.zip
#   ./package-suite.sh --check      # 只做校验（各插件 toc 存在、目录齐全），不打包
#   ./package-suite.sh --output DIR # 指定输出目录

set -euo pipefail

# --- 路径解析：脚本所在目录即 plugin ----------------------------------------
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 套件版本号：独立于各插件版本。发布整合包时递增这里。
SUITE_VERSION="0.1.0"
BUNDLE_NAME="WowPlayerSuite-Bundle"

# 纳入整合包的插件：每行 "插件名|相对 plugin 的源目录"。
# 源目录须是解压后要落在 AddOns/ 下的那一层（含 .toc 的目录）。
PLUGINS=(
  "WowPlayerSuite|WowPlayerSuite"
  "MyChat|chat/MyChat"
  "RoleManager|role-manager/RoleManager"
  "CombatCoach|enhancement/CombatCoach"
  "QuickDisenchant|trade/quick-disenchant/QuickDisenchant"
  "Sudoku|mini-game/Sudoku"
)

CHECK_ONLY=0
OUTPUT_DIR="${PLUGIN_DIR}/dist"

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
fail()  { red "错误: $*"; exit 1; }

echo "整合包:   $BUNDLE_NAME"
echo "套件版本: $SUITE_VERSION"
echo "纳入插件: ${#PLUGINS[@]} 个"
echo

# --- 校验各插件目录与 toc ----------------------------------------------------
MISSING=0
for entry in "${PLUGINS[@]}"; do
  name="${entry%%|*}"
  rel="${entry##*|}"
  src="${PLUGIN_DIR}/${rel}"
  toc="${src}/${name}.toc"
  if [[ ! -d "$src" ]]; then
    red "  缺失目录: $rel"
    MISSING=$((MISSING + 1))
  elif [[ ! -f "$toc" ]]; then
    red "  缺失 TOC: ${rel}/${name}.toc"
    MISSING=$((MISSING + 1))
  else
    ver="$(grep -i '^## Version:' "$toc" | head -n1 | sed 's/^## *[Vv]ersion: *//' | tr -d '\r' | xargs || true)"
    green "  ✓ ${name}  v${ver:-?}  (${rel})"
  fi
done
[[ "$MISSING" -eq 0 ]] || fail "$MISSING 个插件目录/TOC 缺失"

# --- 交叉核对：整包成员须与 Discovery.lua 里 bundled=true 的条目一致 ---------
# 单一运行时清单是 Discovery.lua 的 KNOWN 表；本脚本的 PLUGINS 决定实际打包
# 哪些目录。两者必须对齐（除 Hub 自身 WowPlayerSuite 不在 KNOWN 里），否则会
# 出现"打进包却没被 Hub 管理"或"被管理却漏打包"的偏差。详见接入与打包规范。
DISCOVERY_FILE="${PLUGIN_DIR}/WowPlayerSuite/Discovery.lua"
if [[ -f "$DISCOVERY_FILE" ]]; then
  # 从 KNOWN 里取出所有 bundled = true 行的 addon = "名字"。
  KNOWN_BUNDLED="$(grep -E 'bundled\s*=\s*true' "$DISCOVERY_FILE" \
    | grep -oE 'addon\s*=\s*"[^"]+"' \
    | sed -E 's/.*"([^"]+)".*/\1/' | sort -u || true)"

  # 本脚本 PLUGINS 里除 Hub 外的插件名。
  PKG_MEMBERS="$(for e in "${PLUGINS[@]}"; do n="${e%%|*}"; [[ "$n" == "WowPlayerSuite" ]] || echo "$n"; done | sort -u)"

  MISMATCH=0
  # 在 KNOWN(bundled) 但不在打包列表 → 漏打包。
  while IFS= read -r a; do
    [[ -z "$a" ]] && continue
    if ! grep -qxF "$a" <<< "$PKG_MEMBERS"; then
      red "  不一致: $a 在 Discovery.KNOWN(bundled=true) 中，但未在 package-suite.sh 的 PLUGINS 里"
      MISMATCH=$((MISMATCH + 1))
    fi
  done <<< "$KNOWN_BUNDLED"
  # 在打包列表但不在 KNOWN(bundled) → 打进包却不被管理。
  while IFS= read -r a; do
    [[ -z "$a" ]] && continue
    if ! grep -qxF "$a" <<< "$KNOWN_BUNDLED"; then
      red "  不一致: $a 在 package-suite.sh 的 PLUGINS 里，但未在 Discovery.KNOWN 标记 bundled=true"
      MISMATCH=$((MISMATCH + 1))
    fi
  done <<< "$PKG_MEMBERS"

  [[ "$MISMATCH" -eq 0 ]] || fail "整包成员与 Discovery.KNOWN 不一致（$MISMATCH 处），请同步后重试。"
  green "整包成员与 Discovery.KNOWN(bundled=true) 一致校验通过"

  # --- 目录即分类：校验每个成员的 category 与其源目录一级目录名一致 --------
  # 约定 plugin/ 下一级目录 = 一个分类；Discovery.KNOWN 每条 category 必须等于
  # 该插件所在的一级目录名。写错分类名会导致概览页分组错乱，故在此拦截。
  CAT_MISMATCH=0
  for e in "${PLUGINS[@]}"; do
    name="${e%%|*}"
    rel="${e##*|}"
    [[ "$name" == "WowPlayerSuite" ]] && continue   # Hub 无分类
    topdir="${rel%%/*}"                              # 源目录的一级目录名
    # 从 Discovery.lua 取该 addon 所在行的 category = "值"。
    line="$(grep -E "addon\s*=\s*\"${name}\"" "$DISCOVERY_FILE" | head -n1 || true)"
    cat="$(printf '%s' "$line" | grep -oE 'category\s*=\s*"[^"]+"' | sed -E 's/.*"([^"]+)".*/\1/' || true)"
    if [[ -z "$cat" ]]; then
      red "  分类缺失: $name 在 Discovery.KNOWN 未声明 category"
      CAT_MISMATCH=$((CAT_MISMATCH + 1))
    elif [[ "$cat" != "$topdir" ]]; then
      red "  分类不符: $name 源目录一级=「$topdir」，但 KNOWN category=「$cat」（约定二者相等）"
      CAT_MISMATCH=$((CAT_MISMATCH + 1))
    fi
  done
  [[ "$CAT_MISMATCH" -eq 0 ]] || fail "分类与源目录不一致（$CAT_MISMATCH 处），请对齐后重试。"
  green "分类与源目录一致校验通过（目录即分类）"
else
  yellow "  警告: 未找到 $DISCOVERY_FILE，跳过整包成员一致性校验"
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  green "校验完成（--check，未打包）。"
  exit 0
fi

# --- 暂存并打包 --------------------------------------------------------------
command -v zip >/dev/null 2>&1 || fail "未找到 zip 命令，请先安装 zip"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

for entry in "${PLUGINS[@]}"; do
  name="${entry%%|*}"
  rel="${entry##*|}"
  src="${PLUGIN_DIR}/${rel}"
  # 复制到暂存区，统一以插件名为顶层文件夹。
  cp -R "$src" "${STAGING}/${name}"
done

# 清理暂存区里的开发/系统垃圾，避免进入发布包。
find "$STAGING" -name '.DS_Store' -delete 2>/dev/null || true
find "$STAGING" -name '*.swp' -delete 2>/dev/null || true
find "$STAGING" -name '*.bak' -delete 2>/dev/null || true
find "$STAGING" -name 'package.sh' -delete 2>/dev/null || true
find "$STAGING" -type d -name '.git' -exec rm -rf {} + 2>/dev/null || true

mkdir -p "$OUTPUT_DIR"
ZIP_PATH="${OUTPUT_DIR}/${BUNDLE_NAME}-${SUITE_VERSION}.zip"
rm -f "$ZIP_PATH"

(
  cd "$STAGING"
  zip -r -q -X "$ZIP_PATH" . -x '*.DS_Store'
)

green "打包完成: $ZIP_PATH"
echo "内容预览:"
unzip -l "$ZIP_PATH" | sed 's/^/  /'
