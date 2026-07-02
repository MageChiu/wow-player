// 客户端安装目录相关 API。前端只通过此层调用后端。
import { callCommand, USE_MOCK } from "./tauriClient";
import type {
  WowInstallation,
  GameFlavor,
  PermissionCheckResult,
} from "@/types/domain";
import type {
  ValidateInstallationPathInput,
  AddInstallationInput,
  RemoveInstallationInput,
} from "@/types/command";

function mockPermission(): PermissionCheckResult {
  return { readable: true, writable: true, reason: null };
}

function mockInstallation(
  id: string,
  flavor: GameFlavor,
  rootPath: string,
  displayName: string,
): WowInstallation {
  const now = Math.floor(Date.now() / 1000);
  return {
    id,
    display_name: displayName,
    root_path: rootPath,
    flavor,
    addon_path: `${rootPath}/_${flavor}_/Interface/AddOns`,
    wtf_path: `${rootPath}/_${flavor}_/WTF`,
    is_valid: true,
    permission: mockPermission(),
    created_at: now,
    updated_at: now,
  };
}

const MOCK_ROOT = "/Applications/World of Warcraft";
const mockStore = new Map<string, WowInstallation>();

export async function detectInstallations(): Promise<WowInstallation[]> {
  if (USE_MOCK) {
    return [
      mockInstallation("inst_mock_retail", "retail", MOCK_ROOT, "World of Warcraft (Retail)"),
      mockInstallation("inst_mock_classic", "classic", MOCK_ROOT, "World of Warcraft (Classic)"),
    ];
  }
  return callCommand<WowInstallation[]>("detect_installations");
}

export async function validateInstallationPath(
  input: ValidateInstallationPathInput,
): Promise<WowInstallation> {
  if (USE_MOCK) {
    return mockInstallation(
      "inst_mock_validated",
      "retail",
      input.rootPath,
      "World of Warcraft (Retail)",
    );
  }
  return callCommand<WowInstallation>("validate_installation_path", { input });
}

export async function addInstallation(
  input: AddInstallationInput,
): Promise<WowInstallation[]> {
  if (USE_MOCK) {
    const inst = mockInstallation(
      `inst_mock_${mockStore.size + 1}`,
      "retail",
      input.rootPath,
      input.displayName ?? "World of Warcraft (Retail)",
    );
    mockStore.set(inst.id, inst);
    return [inst];
  }
  return callCommand<WowInstallation[]>("add_installation", { input });
}

export async function listInstallations(): Promise<WowInstallation[]> {
  if (USE_MOCK) {
    return Array.from(mockStore.values());
  }
  return callCommand<WowInstallation[]>("list_installations");
}

export async function removeInstallation(
  input: RemoveInstallationInput,
): Promise<void> {
  if (USE_MOCK) {
    mockStore.delete(input.installationId);
    return;
  }
  return callCommand<void>("remove_installation", { input });
}
