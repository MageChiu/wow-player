// 错误模型，与 src-tauri/src/domain/errors.rs 一一对应。

export type AppErrorCode =
  | "invalid_installation_path"
  | "installation_not_found"
  | "addon_path_not_found"
  | "wtf_path_not_found"
  | "permission_denied"
  | "toc_parse_error"
  | "invalid_zip_file"
  | "no_addon_folder_detected"
  | "multiple_addon_folders_detected"
  | "install_plan_not_found"
  | "install_failed"
  | "rollback_failed"
  | "snapshot_create_failed"
  | "snapshot_restore_failed"
  | "database_error"
  | "provider_error"
  | "network_error"
  | "unsupported_platform"
  | "unknown";

export interface AppError {
  code: AppErrorCode;
  message: string;
  detail: string | null;
  recoverable: boolean;
}

export function isAppError(value: unknown): value is AppError {
  return (
    typeof value === "object" &&
    value !== null &&
    "code" in value &&
    "message" in value
  );
}

// 错误码 -> 用户提示与建议操作（设计规划 §8）。
export interface ErrorPresentation {
  title: string;
  suggestion: string;
}

export const ERROR_PRESENTATION: Partial<Record<AppErrorCode, ErrorPresentation>> = {
  permission_denied: {
    title: "当前目录不可写",
    suggestion: "选择其他目录，或以管理员权限运行。",
  },
  invalid_zip_file: {
    title: "插件压缩包无效",
    suggestion: "请重新选择 zip 文件。",
  },
  no_addon_folder_detected: {
    title: "未识别到插件目录",
    suggestion: "请检查压缩包结构是否包含 .toc 文件。",
  },
  snapshot_restore_failed: {
    title: "配置恢复失败",
    suggestion: "可使用自动备份进行回滚。",
  },
  provider_error: {
    title: "插件源请求失败",
    suggestion: "请稍后重试，或切换插件源。",
  },
  invalid_installation_path: {
    title: "无效的客户端目录",
    suggestion: "请选择 World of Warcraft 根目录。",
  },
};

export function presentError(err: AppError): ErrorPresentation {
  return (
    ERROR_PRESENTATION[err.code] ?? {
      title: err.message || "发生未知错误",
      suggestion: err.detail ?? "请重试或查看日志。",
    }
  );
}
