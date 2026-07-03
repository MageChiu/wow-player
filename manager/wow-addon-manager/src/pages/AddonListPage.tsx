import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { PageHeader } from "@/components/PageHeader";
import { ErrorBanner, EmptyState, Loading } from "@/components/Feedback";
import { Modal } from "@/components/Modal";
import { useInstallationStore } from "@/stores/installationStore";
import { toast } from "@/stores/toastStore";
import { scanAddons, listAddons } from "@/services/addonApi";
import {
  createInstallPlanFromZip,
  executeInstallPlan,
} from "@/services/installerApi";
import { pickZipFile } from "@/services/dialogApi";
import type { LocalAddon, InstallPlan, AddonStatus } from "@/types/domain";
import type { AppError } from "@/types/errors";

const STATUS_LABEL: Record<AddonStatus, string> = {
  installed: "已安装",
  disabled: "已禁用",
  missing_dependency: "缺少依赖",
  update_available: "可更新",
  broken: "损坏",
  unknown: "未知",
};

function statusBadgeClass(status: AddonStatus): string {
  if (status === "installed") return "badge-ok";
  if (status === "broken" || status === "missing_dependency") return "badge-error";
  if (status === "update_available") return "badge-warn";
  return "badge-muted";
}

export function AddonListPage() {
  const current = useInstallationStore((s) => s.current());

  const [addons, setAddons] = useState<LocalAddon[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<AppError | null>(null);
  const [keyword, setKeyword] = useState("");
  const [statusFilter, setStatusFilter] = useState<AddonStatus | "all">("all");
  const [detail, setDetail] = useState<LocalAddon | null>(null);

  // 安装弹窗状态。
  const [installOpen, setInstallOpen] = useState(false);
  const [plan, setPlan] = useState<InstallPlan | null>(null);
  const [planBusy, setPlanBusy] = useState(false);

  useEffect(() => {
    if (!current) return;
    setError(null);
    void (async () => {
      setLoading(true);
      try {
        setAddons(await listAddons({ installationId: current.id }));
      } catch (err) {
        setError(err as AppError);
      } finally {
        setLoading(false);
      }
    })();
  }, [current]);

  async function handleScan() {
    if (!current) return;
    setLoading(true);
    setError(null);
    try {
      const a = await scanAddons({ installationId: current.id });
      setAddons(a);
      toast.ok(`扫描完成，共 ${a.length} 个插件`);
    } catch (err) {
      setError(err as AppError);
      toast.error("扫描失败");
    } finally {
      setLoading(false);
    }
  }

  async function handlePickZip() {
    if (!current) return;
    const zip = await pickZipFile();
    if (!zip) return;
    setPlanBusy(true);
    setError(null);
    try {
      const p = await createInstallPlanFromZip({
        installationId: current.id,
        zipPath: zip,
      });
      setPlan(p);
      setInstallOpen(true);
    } catch (err) {
      setError(err as AppError);
      toast.error("解析压缩包失败");
    } finally {
      setPlanBusy(false);
    }
  }

  async function handleConfirmInstall() {
    if (!plan || !current) return;
    setPlanBusy(true);
    try {
      const result = await executeInstallPlan({ planId: plan.id });
      toast.ok(result.message ?? "安装完成");
      setInstallOpen(false);
      setPlan(null);
      setAddons(await listAddons({ installationId: current.id }));
    } catch (err) {
      setError(err as AppError);
      toast.error("安装失败，已自动回滚");
      setInstallOpen(false);
    } finally {
      setPlanBusy(false);
    }
  }

  if (!current) {
    return (
      <>
        <PageHeader title="插件列表" />
        <div className="card">
          <EmptyState label="请先在设置中添加客户端目录。" />
          <div style={{ textAlign: "center" }}>
            <Link to="/settings">
              <button className="primary">前往设置</button>
            </Link>
          </div>
        </div>
      </>
    );
  }

  const filtered = addons.filter((a) => {
    const matchKw =
      !keyword ||
      (a.title ?? "").toLowerCase().includes(keyword.toLowerCase()) ||
      a.folder_name.toLowerCase().includes(keyword.toLowerCase());
    const matchStatus = statusFilter === "all" || a.status === statusFilter;
    return matchKw && matchStatus;
  });

  return (
    <>
      <PageHeader
        title="插件列表"
        subtitle={current.display_name}
        actions={
          <>
            <button onClick={() => void handleScan()} disabled={loading}>
              扫描插件
            </button>
            <button className="primary" onClick={() => void handlePickZip()} disabled={planBusy}>
              安装 zip
            </button>
          </>
        }
      />

      <ErrorBanner error={error} />

      <div className="toolbar">
        <input
          className="grow"
          placeholder="搜索插件名或目录…"
          value={keyword}
          onChange={(e) => setKeyword(e.target.value)}
        />
        <select
          className="select-inline"
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value as AddonStatus | "all")}
        >
          <option value="all">全部状态</option>
          <option value="installed">已安装</option>
          <option value="disabled">已禁用</option>
          <option value="update_available">可更新</option>
          <option value="broken">损坏</option>
        </select>
      </div>

      <div className="card">
        {loading ? (
          <Loading label="加载插件…" />
        ) : filtered.length === 0 ? (
          <EmptyState label="没有匹配的插件。点击“扫描插件”刷新。" />
        ) : (
          <table>
            <thead>
              <tr>
                <th>插件名</th>
                <th>目录</th>
                <th>版本</th>
                <th>来源</th>
                <th>状态</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {filtered.map((a) => (
                <tr key={a.id}>
                  <td>{a.title || <span className="muted">（无标题）</span>}</td>
                  <td className="mono">{a.folder_name}</td>
                  <td>{a.version ?? "-"}</td>
                  <td>{a.provider ?? "本地"}</td>
                  <td>
                    <span className={`badge ${statusBadgeClass(a.status)}`}>
                      {STATUS_LABEL[a.status]}
                    </span>
                  </td>
                  <td style={{ textAlign: "right" }}>
                    <button className="small" onClick={() => setDetail(a)}>
                      详情
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* 详情弹窗 */}
      <Modal
        title={detail?.title || detail?.folder_name || "插件详情"}
        open={detail !== null}
        onClose={() => setDetail(null)}
        footer={<button onClick={() => setDetail(null)}>关闭</button>}
      >
        {detail && (
          <>
            <div className="row"><span className="row-key">目录</span><span className="mono">{detail.folder_name}</span></div>
            <div className="row"><span className="row-key">版本</span><span>{detail.version ?? "-"}</span></div>
            <div className="row"><span className="row-key">作者</span><span>{detail.author ?? "-"}</span></div>
            <div className="row"><span className="row-key">接口版本</span><span>{detail.interface_version ?? "-"}</span></div>
            <div className="row"><span className="row-key">依赖</span><span>{detail.dependencies.join(", ") || "无"}</span></div>
            <div className="row"><span className="row-key">状态</span><span>{STATUS_LABEL[detail.status]}</span></div>
            {detail.notes && <p className="muted" style={{ marginTop: 12 }}>{detail.notes}</p>}
          </>
        )}
      </Modal>

      {/* 安装计划弹窗 */}
      <Modal
        title="安装预览"
        open={installOpen}
        onClose={() => !planBusy && setInstallOpen(false)}
        footer={
          <>
            <button onClick={() => setInstallOpen(false)} disabled={planBusy}>
              取消
            </button>
            <button className="primary" onClick={() => void handleConfirmInstall()} disabled={planBusy}>
              {planBusy ? "安装中…" : "确认安装"}
            </button>
          </>
        }
      >
        {plan && (
          <>
            <div className="card-title">将安装以下插件目录</div>
            {plan.detected_addon_folders.length === 0 ? (
              <EmptyState label="未识别到插件目录" />
            ) : (
              <ul>
                {plan.detected_addon_folders.map((d) => (
                  <li key={d.folder_name}>
                    <span className="mono">{d.folder_name}</span>
                    {!d.toc_present && <span className="badge badge-warn" style={{ marginLeft: 8 }}>无 .toc</span>}
                  </li>
                ))}
              </ul>
            )}
            {plan.warnings.length > 0 && (
              <div className="banner banner-error" style={{ marginTop: 12 }}>
                {plan.warnings.map((w, i) => (
                  <div key={i}>{w}</div>
                ))}
              </div>
            )}
            {plan.backup_path && (
              <p className="muted">更新前会自动备份到：<span className="mono">{plan.backup_path}</span></p>
            )}
          </>
        )}
      </Modal>
    </>
  );
}
