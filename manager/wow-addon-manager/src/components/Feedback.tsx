import { presentError, type AppError } from "@/types/errors";

export function ErrorBanner({ error }: { error: AppError | null }) {
  if (!error) return null;
  const p = presentError(error);
  return (
    <div className="banner banner-error">
      <div className="banner-title">{p.title}</div>
      <div>{p.suggestion}</div>
      {error.detail && <div className="mono" style={{ marginTop: 6 }}>{error.detail}</div>}
    </div>
  );
}

export function Loading({ label = "加载中…" }: { label?: string }) {
  return <div className="loading">{label}</div>;
}

export function EmptyState({ label }: { label: string }) {
  return <div className="empty">{label}</div>;
}
