import './category-label.css';

export type InsightCategory = 'observed' | 'derived' | 'projected';

const labels: Record<InsightCategory, string> = { observed: 'Observed', derived: 'Derived', projected: 'Projected' };

// The glyph repeats the chart's line style: solid observed, dashed trend, dotted projection.
export function CategoryGlyph({ kind }: { kind: InsightCategory }) {
  const dash = kind === 'observed' ? undefined : kind === 'derived' ? '5 3' : '1.5 3';
  return <svg className="insight-category-glyph" width="18" height="6" viewBox="0 0 18 6" aria-hidden="true">
    <line x1="1" y1="3" x2="17" y2="3" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeDasharray={dash} />
  </svg>;
}

export function CategoryLabel({ kind }: { kind: InsightCategory }) {
  return <span className={`insight-category insight-category-${kind}`}><CategoryGlyph kind={kind} />{labels[kind]}</span>;
}
