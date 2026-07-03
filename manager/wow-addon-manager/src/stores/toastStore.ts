// 全局操作日志 / toast 状态。用于展示操作成功与失败提示。
import { create } from "zustand";

export type ToastKind = "ok" | "error" | "info";

export interface Toast {
  id: number;
  kind: ToastKind;
  message: string;
}

interface ToastState {
  toasts: Toast[];
  push: (kind: ToastKind, message: string) => void;
  dismiss: (id: number) => void;
}

let seq = 0;

export const useToastStore = create<ToastState>((set) => ({
  toasts: [],
  push: (kind, message) => {
    seq += 1;
    const id = seq;
    set((s) => ({ toasts: [...s.toasts, { id, kind, message }] }));
    // 自动消失。
    setTimeout(() => {
      set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) }));
    }, 4000);
  },
  dismiss: (id) => set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })),
}));

/** 便捷函数：在非组件上下文触发提示。 */
export const toast = {
  ok: (msg: string) => useToastStore.getState().push("ok", msg),
  error: (msg: string) => useToastStore.getState().push("error", msg),
  info: (msg: string) => useToastStore.getState().push("info", msg),
};
