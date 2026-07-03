// 配置快照相关 API。前端只通过此层调用后端。
import { callCommand, USE_MOCK } from "./tauriClient";
import type { ConfigSnapshot, RestoreResult } from "@/types/domain";
import type {
  CreateConfigSnapshotInput,
  ListConfigSnapshotsInput,
  RestoreConfigSnapshotInput,
  DeleteConfigSnapshotInput,
} from "@/types/command";

const mockStore = new Map<string, ConfigSnapshot[]>();
let mockSeq = 0;

function mockSnapshot(input: CreateConfigSnapshotInput): ConfigSnapshot {
  mockSeq += 1;
  return {
    id: `snapshot_mock_${mockSeq}`,
    installation_id: input.installationId,
    name: input.name,
    scope: input.scope,
    target: input.target ?? null,
    file_path: `/mock/snapshots/${input.installationId}/snapshot_mock_${mockSeq}/wtf.zip`,
    size_bytes: 2048,
    addon_versions: { WeakAuras: "5.12.0" },
    description: input.description ?? null,
    created_at: Math.floor(Date.now() / 1000),
  };
}

export async function createConfigSnapshot(
  input: CreateConfigSnapshotInput,
): Promise<ConfigSnapshot> {
  if (USE_MOCK) {
    const snap = mockSnapshot(input);
    const list = mockStore.get(input.installationId) ?? [];
    list.unshift(snap);
    mockStore.set(input.installationId, list);
    return snap;
  }
  return callCommand<ConfigSnapshot>("create_config_snapshot", { input });
}

export async function listConfigSnapshots(
  input: ListConfigSnapshotsInput,
): Promise<ConfigSnapshot[]> {
  if (USE_MOCK) {
    return mockStore.get(input.installationId) ?? [];
  }
  return callCommand<ConfigSnapshot[]>("list_config_snapshots", { input });
}

export async function restoreConfigSnapshot(
  input: RestoreConfigSnapshotInput,
): Promise<RestoreResult> {
  if (USE_MOCK) {
    return {
      success: true,
      backup_path: "/mock/backups/wtf_backup",
      message: "配置已恢复（mock）",
    };
  }
  return callCommand<RestoreResult>("restore_config_snapshot", { input });
}

export async function deleteConfigSnapshot(
  input: DeleteConfigSnapshotInput,
): Promise<void> {
  if (USE_MOCK) {
    for (const [key, list] of mockStore) {
      mockStore.set(
        key,
        list.filter((s) => s.id !== input.snapshotId),
      );
    }
    return;
  }
  return callCommand<void>("delete_config_snapshot", { input });
}
