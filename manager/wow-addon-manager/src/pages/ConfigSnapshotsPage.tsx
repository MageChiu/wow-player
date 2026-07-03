import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { PageHeader } from "@/components/PageHeader";
import { ErrorBanner, EmptyState, Loading } from "@/components/Feedback";
import { Modal } from "@/components/Modal";
import { useInstallationStore } from "@/stores/installationStore";
import { toast } from "@/stores/toastStore";
import {
  listConfigSnapshots,
  createConfigSnapshot,
  restoreConfigSnapshot,
  deleteConfigSnapshot,
} from "@/services/configApi";
import type { ConfigSnapshot } from "@/types/domain";
import type { AppError } from "@/types/errors";

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

export function ConfigSnapshotsPage() {
  const current = useInstallationStore((s) => s.current());

  const [snapshots, setSnapshots] = useState<ConfigSnapshot[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<AppError | null>(null);
  const [busy, setBusy] = useState(false);

  const [createOpen, setCreateOpen] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [detail, setDetail] = useState<ConfigSnapshot | null>(null);

  async function reload() {
    if (!current) return;
    setLoading(true);
    setError(null);
    try {
      setSnapshots(await listConfigSnapshots({ installationId: current.id }));
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

  async function handleCreate() {
    if (!current || !name.trim()) return;
    setBusy(true);
    setError(null);
    try {
      await createConfigSnapshot({
        installationId: current.id,
        name: name.trim(),
        scope: "full_wtf",
        description: description.trim() || undefined,
      });
      toast.ok("已创建配置快照");
      setCreateOpen(false);
      setName("");
      setDescription("");
      await reload();
    } catch (err) {
      setError(err as AppError);
      toast.error("创建快照失败");
    } finally {
      setBusy(false);
    }
  }

  async function handleRestore(s: ConfigSnapshot) {
    if (!window.confirm(`恢复快照「${s.name}」？当前配置会先自动备份。`)) return;
    setBusy(true);
    setError(null);
    try {
      const r = await restoreConfigSnapshot({
        snapshotId: s.id,
        createBackupBeforeRestore: true,
      });
      toast.ok(r.message ?? "配置已恢复");
    } catch (err) {
      setError(err as AppError);
      toast.error("恢复失败，已回滚");
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete(s: ConfigSnapshot) {
    if (!window.confirm(`删除快照「${s.name}」？此操作不可撤销。`)) return;
    setBusy(true);
    try {
      await deleteConfigSnapshot({ snapshotId: s.id });
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
        <PageHeader title="配置快照" />
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
        title="配置快照"
        subtitle="备份与恢复 WTF 配置目录"
        actions={
          <button className="primary" onClick={() => setCreateOpen(true)} disabled={busy}>
            创建快照
          </button>
        }
      />

      <ErrorBanner error={error} />

      <div className="card">
        {loading ? (
          <Loading label="加载快照…" />
        ) : snapshots.length === 0 ? (
          <EmptyState label="暂无配置快照。点击“创建快照”备份当前 WTF。" />
        ) : (
          <table>
            <thead>
              <tr>
                <th>名称</th>
                <th>大小</th>
                <th>插件数</th>
                <th>创建时间</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {snapshots.map((s) => (
                <tr key={s.id}>
                  <td>{s.name}</td>
                  <td>{formatBytes(s.size_bytes)}</td>
                  <td>{Object.keys(s.addon_versions).length}</td>
                  <td className="muted">{new Date(s.created_at * 1000).toLocaleString()}</td>
                  <td style={{ textAlign: "right" }}>
                    <div className="btn-row" style={{ justifyContent: "flex-end" }}>
                      <button className="small" onClick={() => setDetail(s)}>详情</button>
                      <button className="small" onClick={() => void handleRestore(s)} disabled={busy}>恢复</button>
                      <button className="small danger" onClick={() => void handleDelete(s)} disabled={busy}>删除</button>
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
        title="创建配置快照"
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
          <label>快照名称</label>
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="如：大米更新前" />
        </div>
        <div className="field">
          <label>备注（可选）</label>
          <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={3} />
        </div>
        <p className="muted">将压缩整个 WTF 目录，记录当前插件版本。</p>
      </Modal>

      {/* 详情弹窗 */}
      <Modal
        title={detail ? `${detail.name} · 关联插件版本` : "快照详情"}
        open={detail !== null}
        onClose={() => setDetail(null)}
        footer={<button onClick={() => setDetail(null)}>关闭</button>}
      >
        {detail && (
          Object.keys(detail.addon_versions).length === 0 ? (
            <EmptyState label="未记录插件版本" />
          ) : (
            <table>
              <thead><tr><th>插件</th><th>版本</th></tr></thead>
              <tbody>
                {Object.entries(detail.addon_versions).map(([k, v]) => (
                  <tr key={k}><td className="mono">{k}</td><td>{v}</td></tr>
                ))}
              </tbody>
            </table>
          )
        )}
      </Modal>
    </>
  );
}
