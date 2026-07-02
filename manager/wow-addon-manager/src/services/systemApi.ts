// 系统级 API：健康检查等。
import { callCommand, USE_MOCK } from "./tauriClient";
import type { HealthStatus } from "@/types/domain";

export async function healthCheck(): Promise<HealthStatus> {
  if (USE_MOCK) {
    return {
      ok: true,
      app_version: "0.1.0-mock",
      platform: "mock",
      db_ready: true,
      message: "mock health ok",
    };
  }
  return callCommand<HealthStatus>("health_check");
}
