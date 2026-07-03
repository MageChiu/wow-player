// 领域模型类型定义，与 src-tauri/src/domain 保持一一对应（serde snake_case）。
// 修改此文件时必须同步 Rust 端，反之亦然。

export type GameFlavor =
  | "retail"
  | "classic"
  | "classic_era"
  | "ptr"
  | "unknown";

export type AddonStatus =
  | "installed"
  | "disabled"
  | "missing_dependency"
  | "update_available"
  | "broken"
  | "unknown";

export type AddonProviderKind =
  | "local_zip"
  | "github_release"
  | "wago"
  | "curse_forge"
  | "manual_url";

export type SnapshotScope = "full_wtf" | "account" | "character" | "addon";

export interface PermissionCheckResult {
  readable: boolean;
  writable: boolean;
  reason: string | null;
}

export interface WowInstallation {
  id: string;
  display_name: string;
  root_path: string;
  flavor: GameFlavor;
  addon_path: string;
  wtf_path: string;
  is_valid: boolean;
  permission: PermissionCheckResult;
  created_at: number;
  updated_at: number;
}

export interface LocalAddon {
  id: string;
  installation_id: string;
  folder_name: string;
  normalized_folder_name: string;
  title: string | null;
  version: string | null;
  author: string | null;
  interface_version: string | null;
  notes: string | null;
  dependencies: string[];
  optional_dependencies: string[];
  saved_variables: string[];
  saved_variables_per_character: string[];
  provider: AddonProviderKind | null;
  remote_id: string | null;
  source_url: string | null;
  status: AddonStatus;
  installed_at: number;
  updated_at: number;
}

export interface RemoteAddon {
  provider: AddonProviderKind;
  remote_id: string;
  title: string;
  summary: string | null;
  author: string | null;
  latest_version: string | null;
  game_flavors: GameFlavor[];
  homepage_url: string | null;
  source_url: string | null;
  download_count: number | null;
  updated_at: number | null;
}

export interface AddonFile {
  provider: AddonProviderKind;
  remote_id: string;
  file_id: string;
  file_name: string;
  version: string | null;
  download_url: string;
  checksum: string | null;
  game_flavor: GameFlavor;
  released_at: number | null;
}

export interface DetectedAddonFolder {
  folder_name: string;
  source_path: string;
  toc_present: boolean;
}

export type InstallAction =
  | "backup_existing_folder"
  | "remove_existing_folder"
  | "copy_new_folder"
  | "update_database";

export type InstallSource =
  | { type: "local_zip"; file_path: string }
  | {
      type: "provider";
      provider: AddonProviderKind;
      remote_id: string;
      file_id: string | null;
    }
  | { type: "manual_url"; url: string };

export interface InstallPlan {
  id: string;
  installation_id: string;
  source: InstallSource;
  temp_extract_path: string;
  detected_addon_folders: DetectedAddonFolder[];
  target_addon_path: string;
  backup_path: string | null;
  actions: InstallAction[];
  warnings: string[];
}

export interface InstallResult {
  success: boolean;
  installed_addons: LocalAddon[];
  backup_path: string | null;
  rollback_available: boolean;
  message: string | null;
}

export interface RestoreResult {
  success: boolean;
  backup_path: string | null;
  message: string | null;
}

export interface ConfigSnapshot {
  id: string;
  installation_id: string;
  name: string;
  scope: SnapshotScope;
  target: string | null;
  file_path: string;
  size_bytes: number;
  addon_versions: Record<string, string>;
  description: string | null;
  created_at: number;
}

export interface Profile {
  id: string;
  installation_id: string;
  name: string;
  description: string | null;
  addon_folder_names: string[];
  snapshot_id: string | null;
  created_at: number;
  updated_at: number;
}

export interface ApplyProfileResult {
  success: boolean;
  snapshot_id: string | null;
  enabled: string[];
  disabled: string[];
  message: string | null;
}

export interface AddonUpdateInfo {
  folder_name: string;
  current_version: string | null;
  latest_version: string | null;
  provider: AddonProviderKind | null;
  update_available: boolean;
}

export interface HealthStatus {
  ok: boolean;
  app_version: string;
  platform: string;
  db_ready: boolean;
  message: string;
}
