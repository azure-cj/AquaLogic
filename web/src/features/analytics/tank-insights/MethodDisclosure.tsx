import { CategoryLabel } from './CategoryLabel';

export function MethodDisclosure() {
  return <details className="tank-insights-method">
    <summary>How is this calculated?</summary>
    <dl>
      <div><dt><CategoryLabel kind="derived" /> Trend</dt>
        <dd>Theil–Sen robust slope over the last 6 h of 30-minute medians. Requires 10 of 12 intervals. Robust to occasional sensor spikes.</dd></div>
      <div><dt><CategoryLabel kind="projected" /> Projection</dt>
        <dd>Extends the 6 h trend up to 3 h, using the 90% slope range plus typical reading scatter. Shown only when the trend is clear and the latest reading is current. Not a measurement.</dd></div>
      <div><dt><CategoryLabel kind="derived" /> Stability</dt>
        <dd>Compares the typical 30-minute change over the last 24 h with the same measure over the previous 7 days for this tank.</dd></div>
      <div><dt><CategoryLabel kind="derived" /> Species range</dt>
        <dd>Overlap of the configured preferred ranges of all species assigned to this tank.</dd></div>
    </dl>
    <p>No machine learning is used. Insights are advisory: they never create alerts or notifications.</p>
  </details>;
}
