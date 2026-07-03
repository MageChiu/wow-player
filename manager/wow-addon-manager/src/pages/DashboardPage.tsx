import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { PageHeader } from "@/components/PageHeader";
import { ErrorBanner, EmptyState, Loading } from "@/components/Feedback";
import { useInstallationStore } from "@/stores/installationStore";
import { toast } from "@/stores/toastStore";
import { scanAddons, listAddons } from "@/services/addonApi";
import { listConfigSnapshots } from "@/services/configApi";
import { checkAddonUpdates } from "@/services/providerApi";
import type { LocalAddon, ConfigSnapshot, AddonUpdateInfo } from "@/types/domain";
import type { AppError } from "@/types/errors";

export function DashboardPage() {
  const current = useInstallationStore((s) => s.current());
  const loading = useInstallationStore((s) => s.loading);

  const [addons, setAddons] = useState<LocalAddon[]>([]);
  const [snapshots, setSnapshots] = useState<ConfigSnapshot[]>([]);
  const [updates, setUpdates] = useState<AddonUpdateInfo[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<AppError | null>(null);

  useEffect(() => {
    if (!current) return;
    setError(null);
    void (async () => {
      try {
        const [a, s] = await Promise.all([
          listAddons({ installationId: current.id }),
          listConfigSnapshots({ installationId: current.id }),
        ]);
        setAddons(a);
        setSnapshots(s);
      } catch (err) {
        setError(err as AppError);
      }
    })();
  }, [current]);

  async function handleScan() {
    if (!current) return;
    setBusy(true);
    setError(null);
    try {
      const a = await scanAddons({ installationId: current.id });
      setAddons(a);
      toast.ok(`扫描完成，共 ${a.length} 个插件`);
    } catch (err) {
      setError(err as AppError);
      toast.error("扫描失败");
    } finally {
      setBusy(false);
    }
  }

  async function handleCheckUpdates() {
    if (!current) return;
    setBusy(true);
    setError(null);
    try {
      const u = await checkAddonUpdates({ installationId: current.id });
      setUpdates(u);
      const n = u.filter((x) => x.update_available).length;
      toast.ok(n > 0 ? `发现 ${n} 个可更新插件` : "全部插件已是最新");
    } catch (err) {
      setError(err as AppError);
      toast.error("检查更新失败");
    } finally {
      setBusy(false);
    }
  }

  if (loading) return <Loading label="加载客户端…" />;

  if (!current) {
    return (
      <>
        <PageHeader title="概览" subtitle="尚未添加 WoW 客户端目录" />
        <div className="card">
          <EmptyState label="还没有配置任何客户端目录。" />
          <div style={{ textAlign: "center" }}>
            <Link to="/settings">
              <button className="primary">前往设置添加客户端</button>
            </Link>
          </div>
        </div>
      </>
    );
  }

  const updatableCount = updates.filter((u) => u.update_available).length;
  const brokenCount = addons.filter((a) => a.status === "broken").length;

  return (
    <>
      <PageHeader
        title="概览"
        subtitle={current.display_name}
        actions={
          <>
            <button onClick={() => void handleScan()} disabled={busy}>
              扫描插件
            </button>
            <button onClick={() => void handleCheckUpdates()} disabled={busy}>
              检查更新
            </button>
            <Link to="/addons">
              <button className="primary">安装 zip</button>
            </Link>
          </>
        }
      />

      <ErrorBanner error={error} />

      <div className="grid grid-3" style={{ marginBottom: 16 }}>
        <div className="stat">
          <div className="stat-label">已安装插件</div>
          <div className="stat-value">{addons.length}</div>
        </div>
        <div className="stat">
          <div className="stat-label">可更新</div>
          <div className="stat-value">{updatableCount}</div>
        </div>
        <div className="stat">
          <div className="stat-label">异常插件</div>
          <div className="stat-value">{brokenCount}</div>
        </div>
      </div>

      <div className="grid grid-2">
        <div className="card">
          <div className="card-title">客户端信息</div>
          <div className="row">
            <span className="row-key">版本类型</span>
            <span>{current.flavor}</span>
          </div>
          <div className="row">
            <span className="row-key">根目录</span>
            <span className="mono">{current.root_path}</span>
          </div>
          <div className="row">
            <span className="row-key">插件目录</span>
            <span className="mono">{current.addon_path}</span>
          </div>
          <div className="row">
            <span className="row-key">可写</span>
            <span className={`badge ${current.permission.writable ? "badge-ok" : "badge-error"}`}>
              {current.permission.writable ? "是" : "否"}
            </span>
          </div>
        </div>

        <div className="card">
          <div className="card-title">最近快照</div>
          {snapshots.length === 0 ? (
            <EmptyState label="暂无配置快照" />
          ) : (
            snapshots.slice(0, 5).map((s) => (
              <div className="row" key={s.id}>
                <span>{s.name}</span>
                <span className="muted">
                  {new Date(s.created_at * 1000).toLocaleString()}
                </span>
              </div>
            ))
          )}
        </div>
      </div>
    </>
  );
}
