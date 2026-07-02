// Command 入参/出参类型（设计规划 §7）。前端只通过 services 层调用，不直接 invoke。

import type {
  WowInstallation,
  LocalAddon,
  InstallPlan,
  InstallResult,
  ConfigSnapshot,
  SnapshotScope,
  RestoreResult,
  Profile,
  ApplyProfileResult,
  RemoteAddon,
  AddonFile,
  AddonProviderKind,
  GameFlavor,
  AddonUpdateInfo,
  HealthStatus,
} from "./domain";

export interface ValidateInstallationPathInput {
  rootPath: string;
}
export interface AddInstallationInput {
  rootPath: string;
  displayName?: string;
}
export interface RemoveInstallationInput {
  installationId: string;
}

export interface ScanAddonsInput {
  installationId: string;
}
export interface ListAddonsInput {
  installationId: string;
}
export interface ToggleAddonInput {
  installationId: string;
  folderName: string;
}
export interface UninstallAddonInput {
  installationId: string;
  folderName: string;
  createBackup: boolean;
}

export interface CreateInstallPlanFromZipInput {
  installationId: string;
  zipPath: string;
}
export interface ExecuteInstallPlanInput {
  planId: string;
}
export interface InstallAddonFromZipInput {
  installationId: string;
  zipPath: string;
}
export interface InstallAddonFromProviderInput {
  installationId: string;
  provider: AddonProviderKind;
  remoteId: string;
  fileId?: string;
}
export interface RollbackInstallInput {
  installationId: string;
  rollbackId: string;
}

export interface CreateConfigSnapshotInput {
  installationId: string;
  name: string;
  scope: SnapshotScope;
  target?: string;
  description?: string;
}
export interface ListConfigSnapshotsInput {
  installationId: string;
}
export interface RestoreConfigSnapshotInput {
  snapshotId: string;
  createBackupBeforeRestore: boolean;
}
export interface DeleteConfigSnapshotInput {
  snapshotId: string;
}

export interface CreateProfileInput {
  installationId: string;
  name: string;
  description?: string;
  addonFolderNames: string[];
  snapshotId?: string;
}
export interface ListProfilesInput {
  installationId: string;
}
export interface UpdateProfileInput {
  profileId: string;
  name?: string;
  description?: string;
  addonFolderNames?: string[];
  snapshotId?: string;
}
export interface ApplyProfileInput {
  profileId: string;
  createSnapshotBeforeApply: boolean;
}
export interface DeleteProfileInput {
  profileId: string;
}

export interface SearchRemoteAddonsInput {
  provider: AddonProviderKind;
  keyword: string;
  gameFlavor?: GameFlavor;
}
export interface GetRemoteAddonFilesInput {
  provider: AddonProviderKind;
  remoteId: string;
  gameFlavor?: GameFlavor;
}
export interface CheckAddonUpdatesInput {
  installationId: string;
}

// 各 API 的返回类型汇总（便于 mock 与真实实现共享签名）。
export type {
  WowInstallation,
  LocalAddon,
  InstallPlan,
  InstallResult,
  ConfigSnapshot,
  RestoreResult,
  Profile,
  ApplyProfileResult,
  RemoteAddon,
  AddonFile,
  AddonUpdateInfo,
  HealthStatus,
};
