// 插件安装相关 API。前端只通过此层调用后端。
import { callCommand, USE_MOCK } from "./tauriClient";
import type { InstallPlan, InstallResult } from "@/types/domain";
import type {
  CreateInstallPlanFromZipInput,
  ExecuteInstallPlanInput,
  InstallAddonFromZipInput,
  RollbackInstallInput,
} from "@/types/command";

function mockPlan(installationId: string, zipPath: string): InstallPlan {
  const folder = "WeakAuras";
  return {
    id: "plan_mock_1",
    installation_id: installationId,
    source: { type: "local_zip", file_path: zipPath },
    temp_extract_path: "/tmp/mock/plan_mock_1",
    detected_addon_folders: [
      { folder_name: folder, source_path: `/tmp/mock/${folder}`, toc_present: true },
    ],
    target_addon_path: `/mock/AddOns`,
    backup_path: null,
    actions: ["copy_new_folder", "update_database"],
    warnings: [],
  };
}

function mockResult(): InstallResult {
  const now = Math.floor(Date.now() / 1000);
  return {
    success: true,
    installed_addons: [
      {
        id: "addon_mock_weakauras",
        installation_id: "inst_mock",
        folder_name: "WeakAuras",
        normalized_folder_name: "WeakAuras",
        title: "WeakAuras",
        version: "5.12.0",
        author: "Mock",
        interface_version: "110002",
        notes: null,
        dependencies: [],
        optional_dependencies: [],
        saved_variables: ["WeakAurasSaved"],
        saved_variables_per_character: [],
        provider: "local_zip",
        remote_id: null,
        source_url: null,
        status: "installed",
        installed_at: now,
        updated_at: now,
      },
    ],
    backup_path: null,
    rollback_available: false,
    message: "成功安装 1 个插件（mock）",
  };
}

export async function createInstallPlanFromZip(
  input: CreateInstallPlanFromZipInput,
): Promise<InstallPlan> {
  if (USE_MOCK) {
    return mockPlan(input.installationId, input.zipPath);
  }
  return callCommand<InstallPlan>("create_install_plan_from_zip", { input });
}

export async function executeInstallPlan(
  input: ExecuteInstallPlanInput,
): Promise<InstallResult> {
  if (USE_MOCK) {
    return mockResult();
  }
  return callCommand<InstallResult>("execute_install_plan", { input });
}

export async function installAddonFromZip(
  input: InstallAddonFromZipInput,
): Promise<InstallResult> {
  if (USE_MOCK) {
    return mockResult();
  }
  return callCommand<InstallResult>("install_addon_from_zip", { input });
}

export async function rollbackInstall(input: RollbackInstallInput): Promise<void> {
  if (USE_MOCK) {
    return;
  }
  return callCommand<void>("rollback_install", { input });
}
