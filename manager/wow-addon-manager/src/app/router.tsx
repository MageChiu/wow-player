import { createHashRouter } from "react-router-dom";
import { AppLayout } from "@/components/layout/AppLayout";
import { DashboardPage } from "@/pages/DashboardPage";
import { AddonListPage } from "@/pages/AddonListPage";
import { AddonMarketPage } from "@/pages/AddonMarketPage";
import { ConfigSnapshotsPage } from "@/pages/ConfigSnapshotsPage";
import { ProfilesPage } from "@/pages/ProfilesPage";
import { SettingsPage } from "@/pages/SettingsPage";

export const router = createHashRouter([
  {
    path: "/",
    element: <AppLayout />,
    children: [
      { index: true, element: <DashboardPage /> },
      { path: "addons", element: <AddonListPage /> },
      { path: "market", element: <AddonMarketPage /> },
      { path: "snapshots", element: <ConfigSnapshotsPage /> },
      { path: "profiles", element: <ProfilesPage /> },
      { path: "settings", element: <SettingsPage /> },
    ],
  },
]);
