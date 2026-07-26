export function RouteLoading({
  label = 'Loading page…',
  variant = 'page',
}: {
  label?: string;
  variant?: 'page' | 'content';
}) {
  if (variant === 'content') {
    return (
      <div
        className="route-loading route-loading-content"
        role="status"
        aria-live="polite"
      >
        <span className="sr-only">{label}</span>
        <span className="route-skeleton-heading" aria-hidden="true" />
        <span className="route-skeleton-subheading" aria-hidden="true" />
        <div className="route-skeleton-grid" aria-hidden="true">
          <span />
          <span />
          <span />
        </div>
        <span className="route-skeleton-panel" aria-hidden="true" />
      </div>
    );
  }

  return (
    <main className="route-loading" role="status" aria-live="polite">
      {label}
    </main>
  );
}
