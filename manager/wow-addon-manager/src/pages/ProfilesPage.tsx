import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { PageHeader } from "@/components/PageHeader";
import { ErrorBanner, EmptyState, Loading } from "@/components/Feedback";
import { Modal } from "@/components/Modal";
import { useInstallationStore } from "@/stores/installationStore";
import { toast } from "@/stores/toastStore";
import {
  listProfiles,
  createProfile,
  applyProfile,
  deleteProfile,
} from "@/services/profileApi";
import { listAddons } from "@/services/addonApi";
import { listConfigSnapshots } from "@/services/configApi";
import type { Profile, LocalAddon, ConfigSnapshot } from "@/types/domain";
import type { AppError } from "@/types/errors";

export function ProfilesPage() {
  const current = useInstallationStore((s) => s.current());

  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [addons, setAddons] = useState<LocalAddon[]>([]);
  const [snapshots, setSnapshots] = useState<ConfigSnapshot[]>([]);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<AppError | null>(null);

  // 创建弹窗。
  const [createOpen, setCreateOpen] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [selectedFolders, setSelectedFolders] = useState<Set<string>>(new Set());
  const [snapshotId, setSnapshotId] = useState("");

  async function reload() {
    if (!current) return;
    setLoading(true);
    setError(null);
    try {
      const [p, a, s] = await Promise.all([
        listProfiles({ installationId: current.id }),
        listAddons({ installationId: current.id }),
        listConfigSnapshots({ installationId: current.id }),
      ]);
      setProfiles(p);
      setAddons(a);
      setSnapshots(s);
    } catch (err) {
      setError(err as AppError);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [current]);

  function toggleFolder(folder: string) {
    setSelectedFolders((prev) => {
      const next = new Set(prev);
      if (next.has(folder)) next.delete(folder);
      else next.add(folder);
      return next;
    });
  }

  async function handleCreate() {
    if (!current || !name.trim()) return;
    setBusy(true);
    setError(null);
    try {
      await createProfile({
        installationId: current.id,
        name: name.trim(),
        description: description.trim() || undefined,
        addonFolderNames: Array.from(selectedFolders),
        snapshotId: snapshotId || undefined,
      });
      toast.ok("已创建配置方案");
      setCreateOpen(false);
      setName("");
      setDescription("");
      setSelectedFolders(new Set());
      setSnapshotId("");
      await reload();
    } catch (err) {
      setError(err as AppError);
      toast.error("创建失败");
    } finally {
      setBusy(false);
    }
  }

  async function handleApply(p: Profile) {
    if (!window.confirm(`应用方案「${p.name}」？将启用方案内插件、禁用其余插件。`)) return;
    setBusy(true);
    setError(null);
    try {
      const r = await applyProfile({ profileId: p.id, createSnapshotBeforeApply: true });
      toast.ok(r.message ?? "已应用方案");
    } catch (err) {
      setError(err as AppError);
      toast.error("应用失败");
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete(p: Profile) {
    if (!window.confirm(`删除方案「${p.name}」？`)) return;
    setBusy(true);
    try {
      await deleteProfile({ profileId: p.id });
      toast.ok("已删除");
      await reload();
    } catch (err) {
      setError(err as AppError);
      toast.error("删除失败");
    } finally {
      setBusy(false);
    }
  }

  if (!current) {
    return (
      <>
        <PageHeader title="配置方案" />
        <div className="card">
          <EmptyState label="请先在设置中添加客户端目录。" />
          <div style={{ textAlign: "center" }}>
            <Link to="/settings"><button className="primary">前往设置</button></Link>
          </div>
        </div>
      </>
    );
  }

  return (
    <>
      <PageHeader
        title="配置方案"
        subtitle="按用途组合插件，一键启停"
        actions={
          <button className="primary" onClick={() => setCreateOpen(true)} disabled={busy}>
            创建方案
          </button>
        }
      />

      <ErrorBanner error={error} />

      <div className="card">
        {loading ? (
          <Loading label="加载方案…" />
        ) : profiles.length === 0 ? (
          <EmptyState label="暂无配置方案。创建一个来管理插件组合。" />
        ) : (
          <table>
            <thead>
              <tr>
                <th>名称</th>
                <th>插件数</th>
                <th>绑定快照</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {profiles.map((p) => (
                <tr key={p.id}>
                  <td>
                    {p.name}
                    {p.description && <div className="muted">{p.description}</div>}
                  </td>
                  <td>{p.addon_folder_names.length}</td>
                  <td>{p.snapshot_id ? <span className="badge badge-muted">已绑定</span> : "-"}</td>
                  <td style={{ textAlign: "right" }}>
                    <div className="btn-row" style={{ justifyContent: "flex-end" }}>
                      <button className="small primary" onClick={() => void handleApply(p)} disabled={busy}>应用</button>
                      <button className="small danger" onClick={() => void handleDelete(p)} disabled={busy}>删除</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* 创建弹窗 */}
      <Modal
        title="创建配置方案"
        open={createOpen}
        onClose={() => !busy && setCreateOpen(false)}
        footer={
          <>
            <button onClick={() => setCreateOpen(false)} disabled={busy}>取消</button>
            <button className="primary" onClick={() => void handleCreate()} disabled={busy || !name.trim()}>
              {busy ? "创建中…" : "创建"}
            </button>
          </>
        }
      >
        <div className="field">
          <label>方案名称</label>
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="如：团队副本" />
        </div>
        <div className="field">
          <label>备注（可选）</label>
          <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={2} />
        </div>
        <div className="field">
          <label>绑定配置快照（可选）</label>
          <select value={snapshotId} onChange={(e) => setSnapshotId(e.target.value)}>
            <option value="">不绑定</option>
            {snapshots.map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>选择方案内启用的插件（{selectedFolders.size} 个）</label>
          {addons.length === 0 ? (
            <EmptyState label="尚未扫描到插件，请先在插件列表扫描。" />
          ) : (
            <div style={{ maxHeight: 220, overflowY: "auto", border: "1px solid var(--border)", borderRadius: 8, padding: 8 }}>
              {addons.map((a) => (
                <label key={a.id} style={{ display: "flex", alignItems: "center", gap: 8, padding: "4px 0" }}>
                  <input
                    type="checkbox"
                    style={{ width: "auto" }}
                    checked={selectedFolders.has(a.normalized_folder_name)}
                    onChange={() => toggleFolder(a.normalized_folder_name)}
                  />
                  <span>{a.title || a.folder_name}</span>
                  <span className="muted mono">{a.normalized_folder_name}</span>
                </label>
              ))}
            </div>
          )}
        </div>
      </Modal>
    </>
  );
}
