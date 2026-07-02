import { useEffect } from "react";
import { NavLink, Outlet } from "react-router-dom";
import { useInstallationStore } from "@/stores/installationStore";
import { ToastStack } from "@/components/ToastStack";

const NAV = [
  { to: "/", label: "概览", end: true },
  { to: "/addons", label: "插件列表" },
  { to: "/market", label: "插件市场" },
  { to: "/snapshots", label: "配置快照" },
  { to: "/profiles", label: "配置方案" },
  { to: "/settings", label: "设置" },
];

export function AppLayout() {
  const installations = useInstallationStore((s) => s.installations);
  const currentId = useInstallationStore((s) => s.currentId);
  const select = useInstallationStore((s) => s.select);
  const load = useInstallationStore((s) => s.load);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="sidebar-brand">
          WoW 插件管理器
          <small>{import.meta.env.VITE_USE_MOCK === "1" ? "mock 模式" : "桌面版"}</small>
        </div>

        {installations.length > 0 && (
          <div style={{ padding: "0 12px 16px" }}>
            <select
              className="select-inline"
              style={{ width: "100%" }}
              value={currentId ?? ""}
              onChange={(e) => select(e.target.value)}
            >
              {installations.map((i) => (
                <option key={i.id} value={i.id}>
                  {i.display_name}
                </option>
              ))}
            </select>
          </div>
        )}

        <nav>
          {NAV.map((n) => (
            <NavLink
              key={n.to}
              to={n.to}
              end={n.end}
              className={({ isActive }) => `nav-item ${isActive ? "active" : ""}`}
            >
              {n.label}
            </NavLink>
          ))}
        </nav>
      </aside>

      <main className="content">
        <Outlet />
      </main>

      <ToastStack />
    </div>
  );
}
