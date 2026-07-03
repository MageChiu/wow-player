// 文件/目录选择封装。mock 模式（浏览器）下无 Tauri 环境，回退到手动输入。
import { USE_MOCK } from "./tauriClient";

async function openDialog(opts: {
  directory?: boolean;
  filters?: { name: string; extensions: string[] }[];
}): Promise<string | null> {
  const { open } = await import("@tauri-apps/plugin-dialog");
  const result = await open({ multiple: false, ...opts });
  return typeof result === "string" ? result : null;
}

/** 选择一个目录；mock 模式下用 prompt 回退。 */
export async function pickDirectory(): Promise<string | null> {
  if (USE_MOCK) {
    return window.prompt("输入目录路径（mock 模式）") || null;
  }
  return openDialog({ directory: true });
}

/** 选择一个 zip 文件；mock 模式下用 prompt 回退。 */
export async function pickZipFile(): Promise<string | null> {
  if (USE_MOCK) {
    return window.prompt("输入 zip 文件路径（mock 模式）") || null;
  }
  return openDialog({
    directory: false,
    filters: [{ name: "插件压缩包", extensions: ["zip"] }],
  });
}
