import { useState } from "react";
import { PageHeader } from "@/components/PageHeader";
import { ErrorBanner, EmptyState } from "@/components/Feedback";
import { useInstallationStore } from "@/stores/installationStore";
import { toast } from "@/stores/toastStore";
import { pickDirectory } from "@/services/dialogApi";
import type { AppError } from "@/types/errors";

export function SettingsPage() {
  const installations = useInstallationStore((s) => s.installations);
  const detect = useInstallationStore((s) => s.detect);
  const add = useInstallationStore((s) => s.add);
  const remove = useInstallationStore((s) => s.remove);

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<AppError | null>(null);

  async function handleDetect() {
    setBusy(true);
    setError(null);
    try {
      await detect();
      toast.ok("已扫描默认安装位置");
    } catch (err) {
      setError(err as AppError);
      toast.error("检测失败");
    } finally {
      setBusy(false);
    }
  }

  async function handleAdd() {
    const dir = await pickDirectory();
    if (!dir) return;
    setBusy(true);
    setError(null);
    try {
      await add(dir);
      toast.ok("已添加客户端目录");
    } catch (err) {
      setError(err as AppError);
      toast.error("添加失败，请确认目录是 WoW 根目录");
    } finally {
      setBusy(false);
    }
  }

  async function handleRemove(id: string) {
    if (!window.confirm("确定移除此客户端目录吗？（不会删除磁盘文件）")) return;
    setBusy(true);
    try {
      await remove(id);
      toast.ok("已移除");
    } catch (err) {
      setError(err as AppError);
      toast.error("移除失败");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHeader
        title="设置"
        subtitle="管理 WoW 客户端目录与应用偏好"
        actions={
          <>
            <button onClick={() => void handleDetect()} disabled={busy}>
              自动检测
            </button>
            <button className="primary" onClick={() => void handleAdd()} disabled={busy}>
              添加目录
            </button>
          </>
        }
      />

      <ErrorBanner error={error} />

      <div className="card">
        <div className="card-title">客户端目录</div>
        {installations.length === 0 ? (
          <EmptyState label="尚未添加客户端目录。点击“自动检测”或“添加目录”。" />
        ) : (
          <table>
            <thead>
              <tr>
                <th>名称</th>
                <th>版本</th>
                <th>根目录</th>
                <th>状态</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {installations.map((i) => (
                <tr key={i.id}>
                  <td>{i.display_name}</td>
                  <td>{i.flavor}</td>
                  <td className="mono">{i.root_path}</td>
                  <td>
                    <span className={`badge ${i.is_valid ? "badge-ok" : "badge-error"}`}>
                      {i.is_valid ? "有效" : "无效"}
                    </span>
                  </td>
                  <td style={{ textAlign: "right" }}>
                    <button className="small danger" onClick={() => void handleRemove(i.id)}>
                      移除
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card">
        <div className="card-title">应用信息</div>
        <div className="row">
          <span className="row-key">默认插件源</span>
          <span>GitHub Release / 手动 URL</span>
        </div>
        <div className="row">
          <span className="row-key">运行模式</span>
          <span>{import.meta.env.VITE_USE_MOCK === "1" ? "mock（浏览器）" : "真实后端"}</span>
        </div>
        <div className="row">
          <span className="row-key">数据与日志</span>
          <span className="muted">由平台应用数据目录管理</span>
        </div>
      </div>
    </>
  );
}
