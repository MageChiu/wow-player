// 插件源（Provider）相关 API。前端只通过此层调用后端。
import { callCommand, USE_MOCK } from "./tauriClient";
import type {
  RemoteAddon,
  AddonFile,
  InstallResult,
  AddonUpdateInfo,
} from "@/types/domain";
import type {
  SearchRemoteAddonsInput,
  GetRemoteAddonFilesInput,
  InstallAddonFromProviderInput,
  CheckAddonUpdatesInput,
} from "@/types/command";

function mockRemoteAddon(keyword: string): RemoteAddon {
  return {
    provider: "github_release",
    remote_id: "WeakAuras/WeakAuras2",
    title: `${keyword} (mock)`,
    summary: "A powerful addon (mock)",
    author: "WeakAuras",
    latest_version: "5.12.0",
    game_flavors: ["retail"],
    homepage_url: "https://github.com/WeakAuras/WeakAuras2",
    source_url: "https://github.com/WeakAuras/WeakAuras2",
    download_count: 1234,
    updated_at: null,
  };
}

function mockAddonFile(remoteId: string): AddonFile {
  return {
    provider: "github_release",
    remote_id: remoteId,
    file_id: "1",
    file_name: "WeakAuras-5.12.0.zip",
    version: "5.12.0",
    download_url: "https://gh/dl/wa.zip",
    checksum: null,
    game_flavor: "retail",
    released_at: null,
  };
}

export async function searchRemoteAddons(
  input: SearchRemoteAddonsInput,
): Promise<RemoteAddon[]> {
  if (USE_MOCK) {
    return input.keyword.trim() ? [mockRemoteAddon(input.keyword)] : [];
  }
  return callCommand<RemoteAddon[]>("search_remote_addons", { input });
}

export async function getRemoteAddonFiles(
  input: GetRemoteAddonFilesInput,
): Promise<AddonFile[]> {
  if (USE_MOCK) {
    return [mockAddonFile(input.remoteId)];
  }
  return callCommand<AddonFile[]>("get_remote_addon_files", { input });
}

export async function installAddonFromProvider(
  input: InstallAddonFromProviderInput,
): Promise<InstallResult> {
  if (USE_MOCK) {
    const now = Math.floor(Date.now() / 1000);
    return {
      success: true,
      installed_addons: [
        {
          id: "addon_mock_provider",
          installation_id: input.installationId,
          folder_name: "WeakAuras",
          normalized_folder_name: "WeakAuras",
          title: "WeakAuras",
          version: "5.12.0",
          author: "Mock",
          interface_version: "110002",
          notes: null,
          dependencies: [],
          optional_dependencies: [],
          saved_variables: [],
          saved_variables_per_character: [],
          provider: input.provider,
          remote_id: input.remoteId,
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
  return callCommand<InstallResult>("install_addon_from_provider", { input });
}

export async function checkAddonUpdates(
  input: CheckAddonUpdatesInput,
): Promise<AddonUpdateInfo[]> {
  if (USE_MOCK) {
    return [
      {
        folder_name: "WeakAuras",
        current_version: "5.11.0",
        latest_version: "5.12.0",
        provider: "github_release",
        update_available: true,
      },
    ];
  }
  return callCommand<AddonUpdateInfo[]>("check_addon_updates", { input });
}
