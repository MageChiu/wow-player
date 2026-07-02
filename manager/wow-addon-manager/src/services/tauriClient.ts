// 统一的 Tauri command 调用封装。
// 所有后端调用都必须经过此处，禁止组件内直接 invoke。
// 错误统一归一化为 AppError。

import { invoke } from "@tauri-apps/api/core";
import { isAppError, type AppError } from "@/types/errors";

export const USE_MOCK = import.meta.env.VITE_USE_MOCK === "1";

function normalizeError(err: unknown): AppError {
  if (isAppError(err)) return err;
  if (typeof err === "string") {
    return { code: "unknown", message: err, detail: null, recoverable: false };
  }
  return {
    code: "unknown",
    message: "调用后端失败",
    detail: err instanceof Error ? err.message : String(err),
    recoverable: false,
  };
}

export async function callCommand<T>(
  command: string,
  args?: Record<string, unknown>,
): Promise<T> {
  try {
    return await invoke<T>(command, args);
  } catch (err) {
    throw normalizeError(err);
  }
}
