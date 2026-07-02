// 插件扫描/列表相关 API。前端只通过此层调用后端。
import { callCommand, USE_MOCK } from "./tauriClient";
import type { LocalAddon, AddonStatus } from "@/types/domain";
import type { ScanAddonsInput, ListAddonsInput } from "@/types/command";

function mockAddon(
  installationId: string,
  folderName: string,
  title: string,
  version: string,
  status: AddonStatus,
): LocalAddon {
  const now = Math.floor(Date.now() / 1000);
  const normalized = folderName.replace(/\.disabled$/, "");
  return {
    id: `addon_${installationId}_${normalized.toLowerCase()}`,
    installation_id: installationId,
    folder_name: folderName,
    normalized_folder_name: normalized,
    title,
    version,
    author: "Mock Author",
    interface_version: "110002",
    notes: `${title} 的说明`,
    dependencies: [],
    optional_dependencies: [],
    saved_variables: [`${normalized}Saved`],
    saved_variables_per_character: [],
    provider: null,
    remote_id: null,
    source_url: null,
    status,
    installed_at: now,
    updated_at: now,
  };
}

const mockAddonStore = new Map<string, LocalAddon[]>();

function buildMockAddons(installationId: string): LocalAddon[] {
  return [
    mockAddon(installationId, "WeakAuras", "WeakAuras", "5.12.0", "installed"),
    mockAddon(installationId, "Details", "Details!", "11.0.2", "installed"),
    mockAddon(installationId, "BrokenAddon", "", "", "broken"),
    mockAddon(installationId, "OldAddon.disabled", "OldAddon", "1.0.0", "disabled"),
  ];
}

export async function scanAddons(input: ScanAddonsInput): Promise<LocalAddon[]> {
  if (USE_MOCK) {
    const addons = buildMockAddons(input.installationId);
    mockAddonStore.set(input.installationId, addons);
    return addons;
  }
  return callCommand<LocalAddon[]>("scan_addons", { input });
}

export async function listAddons(input: ListAddonsInput): Promise<LocalAddon[]> {
  if (USE_MOCK) {
    return mockAddonStore.get(input.installationId) ?? [];
  }
  return callCommand<LocalAddon[]>("list_addons", { input });
}
