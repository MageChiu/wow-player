// Profile（插件配置方案）相关 API。前端只通过此层调用后端。
import { callCommand, USE_MOCK } from "./tauriClient";
import type { Profile, ApplyProfileResult } from "@/types/domain";
import type {
  CreateProfileInput,
  ListProfilesInput,
  UpdateProfileInput,
  ApplyProfileInput,
  DeleteProfileInput,
} from "@/types/command";

const mockStore = new Map<string, Profile[]>();
let mockSeq = 0;

function findMock(profileId: string): { list: Profile[]; profile: Profile } | null {
  for (const list of mockStore.values()) {
    const profile = list.find((p) => p.id === profileId);
    if (profile) return { list, profile };
  }
  return null;
}

export async function createProfile(input: CreateProfileInput): Promise<Profile> {
  if (USE_MOCK) {
    mockSeq += 1;
    const now = Math.floor(Date.now() / 1000);
    const profile: Profile = {
      id: `profile_mock_${mockSeq}`,
      installation_id: input.installationId,
      name: input.name,
      description: input.description ?? null,
      addon_folder_names: input.addonFolderNames,
      snapshot_id: input.snapshotId ?? null,
      created_at: now,
      updated_at: now,
    };
    const list = mockStore.get(input.installationId) ?? [];
    list.unshift(profile);
    mockStore.set(input.installationId, list);
    return profile;
  }
  return callCommand<Profile>("create_profile", { input });
}

export async function listProfiles(input: ListProfilesInput): Promise<Profile[]> {
  if (USE_MOCK) {
    return mockStore.get(input.installationId) ?? [];
  }
  return callCommand<Profile[]>("list_profiles", { input });
}

export async function updateProfile(input: UpdateProfileInput): Promise<Profile> {
  if (USE_MOCK) {
    const found = findMock(input.profileId);
    if (!found) throw new Error("profile not found (mock)");
    const { profile } = found;
    if (input.name !== undefined) profile.name = input.name;
    if (input.description !== undefined) profile.description = input.description ?? null;
    if (input.addonFolderNames !== undefined)
      profile.addon_folder_names = input.addonFolderNames;
    if (input.snapshotId !== undefined) profile.snapshot_id = input.snapshotId ?? null;
    profile.updated_at = Math.floor(Date.now() / 1000);
    return profile;
  }
  return callCommand<Profile>("update_profile", { input });
}

export async function applyProfile(
  input: ApplyProfileInput,
): Promise<ApplyProfileResult> {
  if (USE_MOCK) {
    const found = findMock(input.profileId);
    return {
      success: true,
      snapshot_id: input.createSnapshotBeforeApply ? "snapshot_mock_apply" : null,
      enabled: found?.profile.addon_folder_names ?? [],
      disabled: [],
      message: "已应用 Profile（mock）",
    };
  }
  return callCommand<ApplyProfileResult>("apply_profile", { input });
}

export async function deleteProfile(input: DeleteProfileInput): Promise<void> {
  if (USE_MOCK) {
    for (const [key, list] of mockStore) {
      mockStore.set(
        key,
        list.filter((p) => p.id !== input.profileId),
      );
    }
    return;
  }
  return callCommand<void>("delete_profile", { input });
}
