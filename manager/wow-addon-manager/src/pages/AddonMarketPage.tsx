import { useState } from "react";
import { Link } from "react-router-dom";
import { PageHeader } from "@/components/PageHeader";
import { ErrorBanner, EmptyState, Loading } from "@/components/Feedback";
import { Modal } from "@/components/Modal";
import { useInstallationStore } from "@/stores/installationStore";
import { toast } from "@/stores/toastStore";
import {
  searchRemoteAddons,
  getRemoteAddonFiles,
  installAddonFromProvider,
} from "@/services/providerApi";
import type { RemoteAddon, AddonFile, AddonProviderKind } from "@/types/domain";
import type { AppError } from "@/types/errors";

const PROVIDERS: { value: AddonProviderKind; label: string }[] = [
  { value: "github_release", label: "GitHub Release" },
  { value: "manual_url", label: "手动 URL" },
];

export function AddonMarketPage() {
  const current = useInstallationStore((s) => s.current());

  const [provider, setProvider] = useState<AddonProviderKind>("github_release");
  const [keyword, setKeyword] = useState("");
  const [results, setResults] = useState<RemoteAddon[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<AppError | null>(null);

  // 文件选择弹窗。
  const [selected, setSelected] = useState<RemoteAddon | null>(null);
  const [files, setFiles] = useState<AddonFile[]>([]);
  const [filesBusy, setFilesBusy] = useState(false);
  const [installing, setInstalling] = useState(false);

  // manual_url 直接输入 URL 安装。
  const [manualUrl, setManualUrl] = useState("");

  async function handleSearch() {
    if (!keyword.trim()) return;
    setLoading(true);
    setError(null);
    try {
      const r = await searchRemoteAddons({ provider, keyword, gameFlavor: current?.flavor });
      setResults(r);
      if (r.length === 0) toast.info("没有找到匹配的插件");
    } catch (err) {
      setError(err as AppError);
      toast.error("搜索失败");
    } finally {
      setLoading(false);
    }
  }

  async function openFiles(addon: RemoteAddon) {
    setSelected(addon);
    setFilesBusy(true);
    setError(null);
    try {
      const f = await getRemoteAddonFiles({
        provider: addon.provider,
        remoteId: addon.remote_id,
        gameFlavor: current?.flavor,
      });
      setFiles(f);
    } catch (err) {
      setError(err as AppError);
      toast.error("获取文件列表失败");
    } finally {
      setFilesBusy(false);
    }
  }

  async function install(remoteId: string, prov: AddonProviderKind, fileId?: string) {
    if (!current) {
      toast.error("请先选择客户端");
      return;
    }
    setInstalling(true);
    setError(null);
    try {
      const result = await installAddonFromProvider({
        installationId: current.id,
        provider: prov,
        remoteId,
        fileId,
      });
      toast.ok(result.message ?? "安装完成");
      setSelected(null);
      setFiles([]);
    } catch (err) {
      setError(err as AppError);
      toast.error("安装失败");
    } finally {
      setInstalling(false);
    }
  }

  if (!current) {
    return (
      <>
        <PageHeader title="插件市场" />
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
      <PageHeader title="插件市场" subtitle="从 GitHub Release 或手动 URL 安装插件" />

      <ErrorBanner error={error} />

      <div className="toolbar">
        <select
          className="select-inline"
          value={provider}
          onChange={(e) => setProvider(e.target.value as AddonProviderKind)}
        >
          {PROVIDERS.map((p) => (
            <option key={p.value} value={p.value}>{p.label}</option>
          ))}
        </select>

        {provider === "manual_url" ? (
          <>
            <input
              className="grow"
              placeholder="https://…/addon.zip"
              value={manualUrl}
              onChange={(e) => setManualUrl(e.target.value)}
            />
            <button
              className="primary"
              disabled={installing || !manualUrl.trim()}
              onClick={() => void install(manualUrl.trim(), "manual_url")}
            >
              {installing ? "安装中…" : "下载并安装"}
            </button>
          </>
        ) : (
          <>
            <input
              className="grow"
              placeholder="搜索 GitHub 仓库（如 WeakAuras）"
              value={keyword}
              onChange={(e) => setKeyword(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && void handleSearch()}
            />
            <button className="primary" onClick={() => void handleSearch()} disabled={loading}>
              搜索
            </button>
          </>
        )}
      </div>

      {provider === "github_release" && (
        <div className="card">
          {loading ? (
            <Loading label="搜索中…" />
          ) : results.length === 0 ? (
            <EmptyState label="输入关键字并搜索 GitHub 上的插件仓库。" />
          ) : (
            <table>
              <thead>
                <tr>
                  <th>仓库</th>
                  <th>简介</th>
                  <th>Star</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {results.map((r) => (
                  <tr key={r.remote_id}>
                    <td>{r.title}</td>
                    <td className="muted">{r.summary ?? "-"}</td>
                    <td>{r.download_count ?? "-"}</td>
                    <td style={{ textAlign: "right" }}>
                      <button className="small" onClick={() => void openFiles(r)}>
                        查看版本
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* 文件选择弹窗 */}
      <Modal
        title={selected ? `${selected.title} · 选择版本` : "选择版本"}
        open={selected !== null}
        onClose={() => !installing && setSelected(null)}
        footer={<button onClick={() => setSelected(null)} disabled={installing}>关闭</button>}
      >
        {filesBusy ? (
          <Loading label="获取文件列表…" />
        ) : files.length === 0 ? (
          <EmptyState label="该仓库没有可安装的 zip 资源。" />
        ) : (
          <table>
            <thead>
              <tr>
                <th>文件</th>
                <th>版本</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {files.map((f) => (
                <tr key={f.file_id}>
                  <td className="mono">{f.file_name}</td>
                  <td>{f.version ?? "-"}</td>
                  <td style={{ textAlign: "right" }}>
                    <button
                      className="small primary"
                      disabled={installing}
                      onClick={() => void install(f.remote_id, f.provider, f.file_id)}
                    >
                      {installing ? "安装中…" : "安装"}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Modal>
    </>
  );
}
