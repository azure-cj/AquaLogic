export function MethodDisclosure() {
  return <details className="tank-insights-method">
    <summary>How is this calculated?</summary>
    <p><strong>Derived trend: </strong>Theil–Sen robust slope over the last 6 h of 30-minute medians. Requires 10 of 12 intervals. Robust to occasional sensor spikes.</p>
    <p><strong>Projected: </strong>Extends the 6 h trend up to 3 h, using the 90% slope range plus typical reading scatter. Shown only when the trend is clear and the latest reading is current. Not a measurement.</p>
    <p><strong>Stability: </strong>Compares the typical 30-minute change over the last 24 h with the same measure over the previous 7 days for this tank.</p>
    <p><strong>Species: </strong>Overlap of the configured preferred ranges of all species assigned to this tank.</p>
  </details>;
}
