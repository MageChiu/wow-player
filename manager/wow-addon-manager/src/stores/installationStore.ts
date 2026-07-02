// 全局 installation 上下文：加载客户端列表、当前选中项、增删。
import { create } from "zustand";
import type { WowInstallation } from "@/types/domain";
import type { AppError } from "@/types/errors";
import {
  detectInstallations,
  listInstallations,
  addInstallation as addInstallationApi,
  removeInstallation as removeInstallationApi,
} from "@/services/installationApi";

interface InstallationState {
  installations: WowInstallation[];
  currentId: string | null;
  loading: boolean;
  error: AppError | null;

  current: () => WowInstallation | null;
  load: () => Promise<void>;
  detect: () => Promise<void>;
  add: (rootPath: string, displayName?: string) => Promise<void>;
  remove: (id: string) => Promise<void>;
  select: (id: string) => void;
}

export const useInstallationStore = create<InstallationState>((set, get) => ({
  installations: [],
  currentId: null,
  loading: false,
  error: null,

  current: () => {
    const { installations, currentId } = get();
    return installations.find((i) => i.id === currentId) ?? installations[0] ?? null;
  },

  load: async () => {
    set({ loading: true, error: null });
    try {
      const list = await listInstallations();
      set((s) => ({
        installations: list,
        currentId: s.currentId ?? list[0]?.id ?? null,
      }));
    } catch (err) {
      set({ error: err as AppError });
    } finally {
      set({ loading: false });
    }
  },

  detect: async () => {
    set({ loading: true, error: null });
    try {
      const detected = await detectInstallations();
      // 合并检测结果到现有列表（按 id 去重）。
      set((s) => {
        const map = new Map(s.installations.map((i) => [i.id, i]));
        for (const d of detected) map.set(d.id, d);
        const merged = Array.from(map.values());
        return { installations: merged, currentId: s.currentId ?? merged[0]?.id ?? null };
      });
    } catch (err) {
      set({ error: err as AppError });
    } finally {
      set({ loading: false });
    }
  },

  add: async (rootPath, displayName) => {
    const list = await addInstallationApi({ rootPath, displayName });
    set((s) => {
      const map = new Map(s.installations.map((i) => [i.id, i]));
      for (const d of list) map.set(d.id, d);
      const merged = Array.from(map.values());
      const newId = list[0]?.id ?? s.currentId;
      return { installations: merged, currentId: newId };
    });
  },

  remove: async (id) => {
    await removeInstallationApi({ installationId: id });
    set((s) => {
      const remaining = s.installations.filter((i) => i.id !== id);
      const currentId = s.currentId === id ? (remaining[0]?.id ?? null) : s.currentId;
      return { installations: remaining, currentId };
    });
  },

  select: (id) => set({ currentId: id }),
}));
