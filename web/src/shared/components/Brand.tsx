export function Brand({ compact = false }: { compact?: boolean; }) {
  return (
    <span className={`brand-lockup ${compact ? 'brand-compact' : ''}`}>
      <img src="/aqualogic-mark.png" alt="" />
      <span>
        Aqua<span>Logic</span>
        {!compact && <small>Operations</small>}
      </span>
    </span>
  );
}
