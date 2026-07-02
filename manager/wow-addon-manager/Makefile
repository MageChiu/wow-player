# wow-addon-manager 统一任务入口
#
# 本地开发、校验、打包、图标生成的单一入口；GitHub Actions 复用同一批目标。
# 前端根目录为本目录，Rust 后端在 src-tauri/。
#
# 用法：make <目标>，或 make help 查看全部目标。
#
# 说明：macOS 自带 GNU Make 3.81，不支持 .ONESHELL/.SHELLFLAGS，
# 因此不依赖它们；node/pnpm 常装在 /usr/local/bin，用 ENV 前缀确保命中。

# 本机 node/pnpm 路径前缀；CI 里 PATH 已就绪，追加不影响。
ENV := PATH="/usr/local/bin:$$PATH"

TAURI_DIR := src-tauri
ICON_SVG := $(TAURI_DIR)/icons/app-icon.svg

.DEFAULT_GOAL := help

.PHONY: help install typecheck fe-build fe lint test be bundle bundle-mac bundle-win icon ci dev clean

help: ## 显示所有可用目标
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## 安装前端依赖（pnpm install）
	$(ENV) pnpm install

typecheck: ## 前端类型检查（tsc --noEmit）
	$(ENV) pnpm typecheck

fe-build: ## 构建前端产物（tsc + vite build）
	$(ENV) pnpm build

fe: typecheck fe-build ## 前端全部校验（类型 + 构建）

lint: ## 后端 clippy（-D warnings 视为错误）
	cd $(TAURI_DIR) && $(ENV) cargo clippy --all-targets -- -D warnings

test: ## 后端测试（单元 + 集成）
	cd $(TAURI_DIR) && $(ENV) cargo test

be: lint test ## 后端全部校验（clippy + test）

icon: ## 从 SVG 重新生成全平台图标集
	$(ENV) cargo tauri icon $(ICON_SVG)

bundle: install ## 打包当前平台桌面产物（tauri build，内置前端构建）
	$(ENV) pnpm tauri build

bundle-mac: install ## 打包 macOS 通用包（Intel + Apple Silicon）
	$(ENV) rustup target add x86_64-apple-darwin aarch64-apple-darwin
	$(ENV) pnpm tauri build --target universal-apple-darwin

bundle-win: install ## 打包 Windows 安装包（msi + nsis，需在 Windows 上执行）
	$(ENV) pnpm tauri build

dev: ## 启动完整桌面应用（Tauri 窗口 + 真实后端）
	$(ENV) pnpm tauri dev

ci: install typecheck fe-build be ## CI 门槛：装依赖 + 前端类型/构建 + 后端 clippy/test

clean: ## 清理构建产物
	rm -rf dist
	cd $(TAURI_DIR) && $(ENV) cargo clean
