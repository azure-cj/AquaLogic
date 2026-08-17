import { api } from '@/shared/api/client';
import type {
  ActuatorAction,
  ActuatorCommand,
  ActuatorCommandHistoryPage,
  ActuatorCommandStatus,
  ActuatorName,
  ActuatorStateSnapshot,
  DeviceActuatorStatus,
  FeederActuatorState,
  FeederScheduleSlot,
  LightActuatorState,
  PumpActuatorState,
} from '@/shared/api/models';
import {
  ConfirmDialog,
  EmptyState,
  ErrorState,
  LoadingState,
  Panel,
  StatusBadge,
  Toast,
} from '@/shared/components/admin-ui';
import { formatDate, relativeTime } from '@/shared/utils/formatting';
import { keepPreviousData, useQuery, useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, ArrowRight, ChevronDown, ChevronLeft, ChevronRight, ChevronUp, Clock3, Info, LockKeyhole, Play, Power, RefreshCw, RotateCcw, Square, Utensils } from 'lucide-react';
import { createPortal } from 'react-dom';
import type { CSSProperties } from 'react';
import { useEffect, useId, useRef, useState } from 'react';
import { Link } from 'react-router-dom';

type LightScheduleForm = {
  enabled: boolean;
  on_time: string;
  off_time: string;
};

const defaultSchedule: LightScheduleForm = {
  enabled: false,
  on_time: '08:00',
  off_time: '18:00',
};

const defaultFeederSchedule: FeederScheduleSlot[] = [
  { enabled: false, time: '08:00' },
  { enabled: false, time: '12:00' },
  { enabled: false, time: '18:00' },
];

const HISTORY_PAGE_SIZE = 10;
const PUMP_COMMAND_EXPIRY_SECONDS = 20;
const PUMP_DISPENSE_DURATIONS = [100, 250, 500, 1_000, 1_500, 2_000];

type HistoryActuatorFilter = 'all' | ActuatorName;
type HistoryStatusFilter = 'all' | ActuatorCommandStatus;
export type ActuatorControlPanelVariant = 'summary' | 'full';
type TooltipPosition = {
  top: number;
  left: number;
  arrowLeft: number;
  placement: 'top' | 'bottom';
};
type PumpConfirmation = { actuator: 'pump_a' | 'pump_b'; action: 'dispense' | 'retract' };

const commandStatusDescription: Record<ActuatorCommandStatus, string> = {
  queued: 'Waiting for bridge — no physical call yet',
  executing: 'Bridge claimed — physical call may be in progress',
  succeeded: 'Physical endpoint reported success',
  failed: 'Physical endpoint call failed',
  expired: 'Never sent to ESP32 — expired in queue',
};

const commandStatusFilterLabel: Record<ActuatorCommandStatus, string> = {
  queued: 'Queued · waiting for bridge',
  executing: 'Executing · bridge claimed',
  succeeded: 'Succeeded · endpoint reported success',
  failed: 'Failed · endpoint call failed',
  expired: 'Expired · never sent to bridge',
};

const actuatorLabels: Record<ActuatorName, string> = {
  uv: 'UV light',
  led: 'Normal LED light',
  feeder: 'Fish feeder',
  pump_a: 'Syringe Pump A',
  pump_b: 'Syringe Pump B',
};

const actionLabels: Record<ActuatorAction, string> = {
  on: 'Turn on',
  off: 'Turn off',
  timer: 'Run timer',
  schedule: 'Update schedule',
  feed_now: 'Feed now',
  config: 'Update configuration',
  dispense: 'Dispense / test',
  stop: 'Stop',
  retract: 'Retract',
};

function formatCommandLabel(command: ActuatorCommand) {
  return `${actuatorLabels[command.actuator]} - ${actionLabels[command.action]}`;
}

function formatDuration(durationMs: unknown) {
  if (typeof durationMs !== 'number' || !Number.isFinite(durationMs)) return null;
  const seconds = durationMs / 1000;
  return `${Number.isInteger(seconds) ? seconds : seconds.toFixed(1)} seconds`;
}

function formatPayloadSummary(command: ActuatorCommand) {
  const payload = command.payload;
  if (command.action === 'timer') {
    const duration = formatDuration(payload.duration_ms);
    return duration ? `Run for ${duration}` : 'Timer configuration';
  }
  if (command.action === 'dispense') {
    const duration = formatDuration(command.payload.duration_ms);
    return duration ? `Test run for ${duration}` : 'Short manual test run';
  }
  if (command.action === 'config') {
    const angle = typeof payload.open_angle === 'number' ? `${payload.open_angle} degrees` : 'configured angle';
    const duration = formatDuration(payload.duration_ms) ?? 'configured duration';
    return `Open ${angle} for ${duration}`;
  }
  if (command.action === 'schedule' && command.actuator !== 'feeder') {
    const enabled = payload.enabled ? 'Enabled' : 'Disabled';
    return `${enabled} - daily ${payload.on_time ?? '—'} to ${payload.off_time ?? '—'}`;
  }
  if (command.action === 'schedule' && command.actuator === 'feeder') {
    const slots = Array.isArray(payload.slots) ? payload.slots : [];
    const enabledSlots = slots.filter((slot) => typeof slot === 'object' && slot !== null && 'enabled' in slot && slot.enabled).length;
    return `${enabledSlots} of ${slots.length || 3} feeding slots enabled`;
  }
  return null;
}

function CommandHistoryTooltip() {
  const tooltipId = useId();
  const [open, setOpen] = useState(false);
  const [position, setPosition] = useState<TooltipPosition | null>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) {
      setPosition(null);
      return;
    }

    const updatePosition = () => {
      const trigger = triggerRef.current;
      if (!trigger) return;
      const rect = trigger.getBoundingClientRect();
      const viewportWidth = Math.max(window.innerWidth, 32);
      const tooltipWidth = Math.min(330, Math.max(0, viewportWidth - 32));
      const maxLeft = Math.max(16, viewportWidth - tooltipWidth - 16);
      const left = Math.min(Math.max(rect.left, 16), maxLeft);
      const estimatedHeight = 112;
      const placement = rect.bottom + 10 + estimatedHeight > window.innerHeight && rect.top > estimatedHeight + 10 ? 'top' : 'bottom';
      const top = placement === 'top' ? rect.top - estimatedHeight - 10 : rect.bottom + 10;
      const arrowLeft = Math.min(
        Math.max(rect.left + rect.width / 2 - left - 5, 14),
        Math.max(14, tooltipWidth - 14),
      );
      setPosition({ top, left, arrowLeft, placement });
    };

    updatePosition();
    window.addEventListener('resize', updatePosition);
    window.addEventListener('scroll', updatePosition, true);
    return () => {
      window.removeEventListener('resize', updatePosition);
      window.removeEventListener('scroll', updatePosition, true);
    };
  }, [open]);

  const tooltipPosition = position ?? { top: 16, left: 16, arrowLeft: 18, placement: 'bottom' as const };
  const tooltip = open && typeof document !== 'undefined' ? createPortal(
    <span
      className="command-history-tooltip"
      id={tooltipId}
      role="tooltip"
      data-placement={tooltipPosition.placement}
      style={{
        top: tooltipPosition.top,
        left: tooltipPosition.left,
        '--tooltip-arrow-left': `${tooltipPosition.arrowLeft}px`,
      } as CSSProperties}
    >
      This audit trail records administrator commands created for this tank&apos;s registered bridge. Queued commands may still be waiting; expired commands were never sent to the ESP32.
    </span>,
    document.body,
  ) : null;

  return (
    <>
      <span
        className="command-history-help"
        onMouseEnter={() => setOpen(true)}
        onMouseLeave={() => setOpen(false)}
        onFocus={() => setOpen(true)}
        onBlur={(event) => {
          if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setOpen(false);
        }}
      >
        <button
          ref={triggerRef}
          className="command-history-help-trigger"
          type="button"
          aria-label="About command history"
          aria-expanded={open}
          aria-describedby={open ? tooltipId : undefined}
          onClick={() => setOpen(true)}
          onKeyDown={(event) => {
            if (event.key === 'Escape') setOpen(false);
          }}
        >
          <Info size={15} aria-hidden="true" />
        </button>
      </span>
      {tooltip}
    </>
  );
}

function CommandDetails({ command }: { command: ActuatorCommand }) {
  const payloadSummary = formatPayloadSummary(command);
  return (
    <div className="command-details" id={`command-details-${command.command_id}`}>
      <dl className="command-details-grid">
        <div><dt>Command ID</dt><dd className="command-id">{command.command_id}</dd></div>
        <div><dt>Requested</dt><dd>{formatDate(command.requested_at)}</dd></div>
        <div><dt>Expires</dt><dd>{formatDate(command.expires_at)}</dd></div>
        <div><dt>Bridge claimed</dt><dd>{command.executing_at ? formatDate(command.executing_at) : 'Not claimed'}</dd></div>
        <div><dt>Physical result</dt><dd>{command.execution_at ? formatDate(command.execution_at) : 'Not reported'}</dd></div>
        <div><dt>Actor</dt><dd>{command.actor_name ?? 'Administrator'}</dd></div>
      </dl>
      {payloadSummary && <p className="command-details-summary"><strong>Validated request</strong><span>{payloadSummary}</span></p>}
      {command.error && <p className="command-details-error"><strong>Reported failure</strong><span>{command.error}</span></p>}
      {command.result && <p className="command-details-result"><strong>Bridge result</strong><span>The bridge returned a completion result for this command.</span></p>}
    </div>
  );
}

const asLightState = (snapshot: ActuatorStateSnapshot | undefined): LightActuatorState | null => {
  const state = snapshot?.state;
  return state && 'on' in state ? state : null;
};

const asFeederState = (snapshot: ActuatorStateSnapshot | undefined): FeederActuatorState | null => {
  const state = snapshot?.state;
  return state && 'feeding' in state ? state : null;
};

const asPumpState = (snapshot: ActuatorStateSnapshot | undefined): PumpActuatorState | null => {
  const state = snapshot?.state;
  return state && 'active' in state && 'dose_count' in state ? state : null;
};

const errorMessage = (error: unknown, fallback: string) =>
  error instanceof Error ? error.message : fallback;

function LightCard({
  actuator,
  state,
  schedule,
  timerSeconds,
  onTimerChange,
  onScheduleChange,
  onCommand,
  busy,
}: {
  actuator: 'uv' | 'led';
  state: LightActuatorState | null;
  schedule: LightScheduleForm;
  timerSeconds: string;
  onTimerChange: (value: string) => void;
  onScheduleChange: (value: LightScheduleForm) => void;
  onCommand: (action: ActuatorAction, payload: Record<string, unknown>, label: string) => void;
  busy: string | null;
}) {
  const label = actuator === 'uv' ? 'UV light' : 'Normal LED light';
  const busyFor = (action: string) => busy === `${actuator}:${action}`;
  return (
    <article className="actuator-card">
      <div className="actuator-card-header">
        <div>
          <p className="actuator-kicker">{actuator === 'uv' ? 'UV sterilization' : 'Aquarium lighting'}</p>
          <h3>{label}</h3>
        </div>
        <span className={`actuator-state ${state?.on ? 'is-on' : state ? 'is-off' : 'is-unknown'}`}>
          <Power size={14} aria-hidden="true" />
          {state ? (state.on ? 'On' : 'Off') : 'Unknown'}
        </span>
      </div>
      <div className="actuator-meta-grid">
        <span><small>Timer remaining</small><strong>{state?.remaining_ms ? `${Math.ceil(state.remaining_ms / 1000)}s` : '—'}</strong></span>
        <span><small>Schedule</small><strong>{state?.schedule_enabled ? `${state.on_time} → ${state.off_time}` : 'Disabled'}</strong></span>
      </div>
      <div className="actuator-actions" aria-label={`${label} manual controls`}>
        <button className="button button-primary" type="button" disabled={Boolean(busy)} onClick={() => onCommand('on', {}, `${label} on`)}>
          On
        </button>
        <button className="button button-secondary" type="button" disabled={Boolean(busy)} onClick={() => onCommand('off', {}, `${label} off`)}>
          Off
        </button>
      </div>
      <div className="actuator-form-row">
        <label className="field">
          <span>Timer duration (seconds)</span>
          <input type="number" min="1" max="86400" step="1" value={timerSeconds} onChange={(event) => onTimerChange(event.target.value)} />
        </label>
        <button className="button button-secondary actuator-form-button" type="button" disabled={Boolean(busy)} onClick={() => onCommand('timer', { duration_ms: Number(timerSeconds) * 1000 }, `${label} timer`)}>
          <Clock3 size={15} /> Start timer
        </button>
      </div>
      <div className="actuator-schedule">
        <div className="actuator-schedule-heading">
          <strong>Daily schedule</strong>
          <label className="toggle-label">
            <input type="checkbox" checked={schedule.enabled} onChange={(event) => onScheduleChange({ ...schedule, enabled: event.target.checked })} />
            Enable
          </label>
        </div>
        <div className="actuator-form-row">
          <label className="field"><span>On time</span><input type="time" value={schedule.on_time} onChange={(event) => onScheduleChange({ ...schedule, on_time: event.target.value })} /></label>
          <label className="field"><span>Off time</span><input type="time" value={schedule.off_time} onChange={(event) => onScheduleChange({ ...schedule, off_time: event.target.value })} /></label>
        </div>
        <button className="button button-secondary" type="button" disabled={Boolean(busy)} onClick={() => onCommand('schedule', schedule, `${label} schedule`)}>
          Save schedule
        </button>
      </div>
      {busyFor('on') && <small className="actuator-busy">Queueing command…</small>}
    </article>
  );
}

function PumpCard({
  actuator,
  state,
  durationMs,
  onDurationChange,
  onDispense,
  onStop,
  onRetract,
  busy,
  disabled,
}: {
  actuator: 'pump_a' | 'pump_b';
  state: PumpActuatorState | null;
  durationMs: string;
  onDurationChange: (value: string) => void;
  onDispense: () => void;
  onStop: () => void;
  onRetract: () => void;
  busy: string | null;
  disabled: boolean;
}) {
  const label = actuator === 'pump_a' ? 'Syringe Pump A' : 'Syringe Pump B';
  const busyFor = (action: string) => busy === `${actuator}:${action}`;
  return (
    <article className="actuator-card pump-card">
      <div className="actuator-card-header">
        <div>
          <p className="actuator-kicker">Dry-run mechanical test</p>
          <h3>{label}</h3>
        </div>
        <span className={`actuator-state ${state?.active ? 'is-on' : state ? 'is-off' : 'is-unknown'}`}>
          <Power size={14} aria-hidden="true" />
          {state ? (state.active ? 'Running' : 'Ready') : 'Unknown'}
        </span>
      </div>
      <div className="actuator-meta-grid">
        <span><small>Test dose count</small><strong>{state?.dose_count ?? '—'}</strong></span>
        <span><small>Configured volume</small><strong>{state ? `${state.volume_ml} mL` : '—'}</strong></span>
        <span><small>Last dispense</small><strong>{state?.last_dispensed ?? '—'}</strong></span>
        <span><small>Bridge access</small><strong>{disabled ? 'Reconnect bridge' : 'Available'}</strong></span>
      </div>
      <label className="field pump-duration-field">
        <span>Dispense/test cutoff</span>
        <select aria-label={`${label} test duration`} value={durationMs} onChange={(event) => onDurationChange(event.target.value)} disabled={disabled || Boolean(busy)}>
          {PUMP_DISPENSE_DURATIONS.map((duration) => <option value={duration} key={duration}>{duration} ms</option>)}
        </select>
      </label>
      <div className="pump-action-grid" aria-label={`${label} manual test controls`}>
        <button className="button button-primary" type="button" aria-label={`${label} dispense/test`} disabled={disabled || Boolean(busy)} onClick={onDispense}>
          <Play size={15} /> Dispense / test
        </button>
        <button className="button button-danger pump-stop-button" type="button" aria-label={`${label} stop`} disabled={disabled || Boolean(busy)} onClick={onStop}>
          <Square size={14} /> Stop
        </button>
        <button className="button button-secondary" type="button" aria-label={`${label} retract`} disabled={disabled || Boolean(busy)} onClick={onRetract}>
          <RotateCcw size={15} /> Retract
        </button>
      </div>
      {disabled && <small className="pump-disabled-note">Reconnect the bridge before sending a pump test. No offline pump command is queued.</small>}
      {busyFor('dispense') && <small className="actuator-busy">Queueing pump test…</small>}
    </article>
  );
}

function BridgeOfflineWarning({ freshness }: { freshness?: DeviceActuatorStatus['device_freshness']; }) {
  return (
    <div className="actuator-offline-warning" role="status">
      <AlertTriangle size={17} aria-hidden="true" />
      <span>
        <strong>Bridge is {freshness === 'unknown' ? 'not reporting' : 'offline or stale'}</strong>
        <small>Light and feeder commands may expire while waiting. Pump manual tests are not queued until the bridge is online.</small>
      </span>
    </div>
  );
}

function SummaryLightCard({
  actuator,
  state,
  busy,
  onCommand,
}: {
  actuator: 'uv' | 'led';
  state: LightActuatorState | null;
  busy: string | null;
  onCommand: (action: 'on' | 'off', label: string) => void;
}) {
  const label = actuator === 'uv' ? 'UV light' : 'Normal LED light';
  return (
    <article className="actuator-summary-card">
      <div className="actuator-summary-card-header">
        <div>
          <p className="actuator-kicker">{actuator === 'uv' ? 'UV sterilization' : 'Aquarium lighting'}</p>
          <h3>{label}</h3>
        </div>
        <span className={`actuator-state ${state?.on ? 'is-on' : state ? 'is-off' : 'is-unknown'}`}>
          <Power size={14} aria-hidden="true" />
          {state ? (state.on ? 'On' : 'Off') : 'Unknown'}
        </span>
      </div>
      <p className="actuator-summary-detail">
        {state?.schedule_enabled ? `Schedule ${state.on_time} -> ${state.off_time}` : 'Schedule disabled'}
        {state?.remaining_ms ? ` · ${Math.ceil(state.remaining_ms / 1000)}s remaining` : ''}
      </p>
      <div className="actuator-summary-actions" aria-label={`${label} quick controls`}>
        <button className="button button-primary button-small" type="button" disabled={Boolean(busy)} onClick={() => onCommand('on', `${label} on`)}>On</button>
        <button className="button button-secondary button-small" type="button" disabled={Boolean(busy)} onClick={() => onCommand('off', `${label} off`)}>Off</button>
      </div>
    </article>
  );
}

function SummaryFeederCard({
  state,
  busy,
  onFeed,
}: {
  state: FeederActuatorState | null;
  busy: string | null;
  onFeed: () => void;
}) {
  return (
    <article className="actuator-summary-card">
      <div className="actuator-summary-card-header">
        <div>
          <p className="actuator-kicker">Portion control</p>
          <h3>Fish feeder</h3>
        </div>
        <span className={`actuator-state ${state?.feeding ? 'is-on' : state ? 'is-off' : 'is-unknown'}`}>
          <Utensils size={14} aria-hidden="true" />
          {state?.feeding ? 'Feeding' : state ? 'Ready' : 'Unknown'}
        </span>
      </div>
      <div className="actuator-summary-stats">
        <span><small>Feed count</small><strong>{state?.feed_count ?? '—'}</strong></span>
        <span><small>Last fed</small><strong>{state?.last_fed ?? '—'}</strong></span>
      </div>
      <button className="button button-primary button-small" type="button" disabled={Boolean(busy)} onClick={onFeed}>
        <Utensils size={14} /> Feed now
      </button>
      <p className="actuator-summary-detail">Configuration and feeding schedules are available in full controls.</p>
    </article>
  );
}

function SummaryPumpCard({ pumpA, pumpB, tankId }: { pumpA: PumpActuatorState | null; pumpB: PumpActuatorState | null; tankId: number; }) {
  const pumpStatus = (state: PumpActuatorState | null) => state ? (state.active ? 'Running' : 'Ready') : 'Unknown';
  return (
    <article className="actuator-summary-card actuator-summary-pumps">
      <div className="actuator-summary-card-header">
        <div>
          <p className="actuator-kicker">Guarded manual tests</p>
          <h3>Syringe pumps</h3>
        </div>
        <span className="actuator-state is-unknown"><Power size={14} aria-hidden="true" />Full page</span>
      </div>
      <div className="actuator-summary-pump-list">
        <span><strong>Pump A</strong><small>{pumpStatus(pumpA)}</small></span>
        <span><strong>Pump B</strong><small>{pumpStatus(pumpB)}</small></span>
      </div>
      <p className="actuator-summary-detail">Dispense, stop, and retract stay on the dedicated page for safer testing.</p>
      <Link className="text-link" to={`/admin/tanks/${tankId}/actuators`}>Open full controls <ArrowRight size={14} /></Link>
    </article>
  );
}

function ActuatorSummary({
  tankId,
  uv,
  led,
  feeder,
  pumpA,
  pumpB,
  busy,
  onCommand,
  onFeed,
}: {
  tankId: number;
  uv: LightActuatorState | null;
  led: LightActuatorState | null;
  feeder: FeederActuatorState | null;
  pumpA: PumpActuatorState | null;
  pumpB: PumpActuatorState | null;
  busy: string | null;
  onCommand: (actuator: 'uv' | 'led', action: 'on' | 'off', label: string) => void;
  onFeed: () => void;
}) {
  return (
    <div className="actuator-summary-grid">
      <SummaryLightCard actuator="uv" state={uv} busy={busy} onCommand={(action, label) => onCommand('uv', action, label)} />
      <SummaryLightCard actuator="led" state={led} busy={busy} onCommand={(action, label) => onCommand('led', action, label)} />
      <SummaryFeederCard state={feeder} busy={busy} onFeed={onFeed} />
      <SummaryPumpCard pumpA={pumpA} pumpB={pumpB} tankId={tankId} />
    </div>
  );
}

export function ActuatorControlPanel({ tankId, variant = 'full' }: { tankId: number; variant?: ActuatorControlPanelVariant }) {
  const fullView = variant === 'full';
  const queryClient = useQueryClient();
  const [busy, setBusy] = useState<string | null>(null);
  const [feedConfirmOpen, setFeedConfirmOpen] = useState(false);
  const [pumpConfirmation, setPumpConfirmation] = useState<PumpConfirmation | null>(null);
  const [feedback, setFeedback] = useState<{ tone: 'success' | 'error'; message: string } | null>(null);
  const [historyPage, setHistoryPage] = useState(1);
  const [historyActuator, setHistoryActuator] = useState<HistoryActuatorFilter>('all');
  const [historyStatus, setHistoryStatus] = useState<HistoryStatusFilter>('all');
  const [expandedCommandId, setExpandedCommandId] = useState<string | null>(null);
  const [uvSchedule, setUvSchedule] = useState<LightScheduleForm>(defaultSchedule);
  const [ledSchedule, setLedSchedule] = useState<LightScheduleForm>(defaultSchedule);
  const [feederSchedule, setFeederSchedule] = useState<FeederScheduleSlot[]>(defaultFeederSchedule);
  const [uvTimer, setUvTimer] = useState('10');
  const [ledTimer, setLedTimer] = useState('10');
  const [feederAngle, setFeederAngle] = useState('125');
  const [feederDuration, setFeederDuration] = useState('1000');
  const [pumpADuration, setPumpADuration] = useState('500');
  const [pumpBDuration, setPumpBDuration] = useState('500');
  const [scheduleInitialized, setScheduleInitialized] = useState(false);

  const status = useQuery({
    queryKey: ['tank-actuator-status', tankId],
    queryFn: () => api<DeviceActuatorStatus>(`/tanks/${tankId}/actuators/status`),
    refetchInterval: 5_000,
  });
  const history = useQuery({
    queryKey: ['tank-actuator-history', tankId, historyPage, HISTORY_PAGE_SIZE, historyActuator, historyStatus],
    queryFn: () => {
      const params = new URLSearchParams({ page: String(historyPage), page_size: String(HISTORY_PAGE_SIZE) });
      if (historyActuator !== 'all') params.set('actuator', historyActuator);
      if (historyStatus !== 'all') params.set('status', historyStatus);
      return api<ActuatorCommandHistoryPage>(`/tanks/${tankId}/actuators/history?${params.toString()}`);
    },
    enabled: fullView,
    placeholderData: keepPreviousData,
    refetchInterval: 5_000,
  });

  useEffect(() => {
    setHistoryPage(1);
    setHistoryActuator('all');
    setHistoryStatus('all');
    setExpandedCommandId(null);
    setFeedback(null);
    setPumpConfirmation(null);
    setScheduleInitialized(false);
  }, [tankId]);

  useEffect(() => {
    if (scheduleInitialized || !status.data) return;
    const uv = asLightState(status.data.actuators.find((item) => item.actuator === 'uv'));
    const led = asLightState(status.data.actuators.find((item) => item.actuator === 'led'));
    const feeder = asFeederState(status.data.actuators.find((item) => item.actuator === 'feeder'));
    if (uv) setUvSchedule({ enabled: uv.schedule_enabled, on_time: uv.on_time, off_time: uv.off_time });
    if (led) setLedSchedule({ enabled: led.schedule_enabled, on_time: led.on_time, off_time: led.off_time });
    if (feeder) {
      setFeederAngle(String(feeder.open_angle));
      setFeederDuration(String(feeder.duration_ms));
      setFeederSchedule(feeder.schedule);
    }
    setScheduleInitialized(true);
  }, [scheduleInitialized, status.data]);

  const clearFeedback = () => setFeedback(null);

  const queueCommand = async (
    actuator: ActuatorName,
    action: ActuatorAction,
    payload: Record<string, unknown>,
    label: string,
    expiresInSeconds?: number,
  ) => {
    clearFeedback();
    const key = `${actuator}:${action}`;
    setBusy(key);
    try {
      const deviceId = status.data?.device_id;
      await api<ActuatorCommand>(`/tanks/${tankId}/actuators/commands`, {
        method: 'POST',
        body: JSON.stringify({ actuator, action, payload, ...(deviceId ? { device_id: deviceId } : {}), ...(expiresInSeconds ? { expires_in_seconds: expiresInSeconds } : {}) }),
      });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['tank-actuator-status', tankId] }),
        queryClient.invalidateQueries({ queryKey: ['tank-actuator-history', tankId] }),
      ]);
      setHistoryPage(1);
      setExpandedCommandId(null);
      setFeedback({ tone: 'success', message: `${label} command queued. The bridge will report the result.` });
    } catch (caught) {
      setFeedback({ tone: 'error', message: errorMessage(caught, `Could not queue the ${label.toLowerCase()} command.`) });
    } finally {
      setBusy(null);
    }
  };

  const snapshots = status.data?.actuators ?? [];
  const uv = asLightState(snapshots.find((item) => item.actuator === 'uv'));
  const led = asLightState(snapshots.find((item) => item.actuator === 'led'));
  const feeder = asFeederState(snapshots.find((item) => item.actuator === 'feeder'));
  const pumpA = asPumpState(snapshots.find((item) => item.actuator === 'pump_a'));
  const pumpB = asPumpState(snapshots.find((item) => item.actuator === 'pump_b'));
  const historyData = history.data;
  const historyStart = historyData?.total ? ((historyData.page - 1) * historyData.page_size) + 1 : 0;
  const historyEnd = historyData ? Math.min(historyData.page * historyData.page_size, historyData.total) : 0;
  const pumpsDisabled = !status.data?.device_online;
  const confirmedPumpLabel = pumpConfirmation ? actuatorLabels[pumpConfirmation.actuator] : '';
  const confirmedPumpDuration = pumpConfirmation?.actuator === 'pump_a' ? pumpADuration : pumpBDuration;

  return (
    <>
      <Toast
        message={feedback?.message ?? ''}
        tone={feedback?.tone ?? 'success'}
        autoDismissMs={feedback?.tone === 'error' ? 0 : 4_500}
        onDismiss={() => setFeedback(null)}
      />
      <Panel
        title={fullView ? 'Actuator controls' : 'Actuator snapshot'}
        description={fullView ? 'Administrator-only controls for the registered bridge device' : 'Quick controls for the registered bridge device'}
        className={`tank-actuator-panel ${fullView ? '' : 'tank-actuator-summary-panel'}`}
        action={fullView ? (
          <span className={`bridge-freshness bridge-${status.data?.device_freshness ?? 'unknown'}`}>
            <span className="bridge-freshness-dot" aria-hidden="true" />
            {status.data?.device_freshness ?? 'unknown'}
          </span>
        ) : (
          <div className="actuator-summary-panel-actions">
            <span className={`bridge-freshness bridge-${status.data?.device_freshness ?? 'unknown'}`}>
              <span className="bridge-freshness-dot" aria-hidden="true" />
              {status.data?.device_freshness ?? 'unknown'}
            </span>
            <Link className="button button-secondary button-small" to={`/admin/tanks/${tankId}/actuators`}>
              Full controls <ArrowRight size={14} />
            </Link>
          </div>
        )}
      >
      {status.isLoading ? (
        <LoadingState label="Loading bridge actuator state…" />
      ) : status.isError ? (
        <ErrorState message="Bridge actuator state could not be loaded. No hardware command was sent." retry={() => status.refetch()} />
      ) : (
        <>
          <div className="bridge-device-summary">
            <span><small>Registered device</small><strong>{status.data?.device_id}</strong></span>
            <span><small>Bridge freshness</small><strong>{status.data?.device_online ? 'Online' : 'Offline / stale'}</strong></span>
            <span><small>Last bridge report</small><strong>{relativeTime(status.data?.last_seen_at)}</strong></span>
            <button className="icon-button" type="button" aria-label="Refresh actuator state" onClick={() => void status.refetch()}><RefreshCw size={16} /></button>
          </div>
          {!status.data?.device_online && <BridgeOfflineWarning freshness={status.data?.device_freshness} />}
          {variant === 'summary' ? (
            <ActuatorSummary
              tankId={tankId}
              uv={uv}
              led={led}
              feeder={feeder}
              pumpA={pumpA}
              pumpB={pumpB}
              busy={busy}
              onCommand={(actuator, action, label) => void queueCommand(actuator, action, {}, label)}
              onFeed={() => setFeedConfirmOpen(true)}
            />
          ) : (
          <>
          <div className="actuator-grid">
            <LightCard actuator="uv" state={uv} schedule={uvSchedule} timerSeconds={uvTimer} onTimerChange={setUvTimer} onScheduleChange={setUvSchedule} onCommand={(action, payload, label) => void queueCommand('uv', action, payload, label)} busy={busy} />
            <LightCard actuator="led" state={led} schedule={ledSchedule} timerSeconds={ledTimer} onTimerChange={setLedTimer} onScheduleChange={setLedSchedule} onCommand={(action, payload, label) => void queueCommand('led', action, payload, label)} busy={busy} />
            <article className="actuator-card feeder-card">
              <div className="actuator-card-header">
                <div><p className="actuator-kicker">Manual portion control</p><h3>Fish feeder</h3></div>
                <span className={`actuator-state ${feeder?.feeding ? 'is-on' : feeder ? 'is-off' : 'is-unknown'}`}><Utensils size={14} aria-hidden="true" />{feeder?.feeding ? 'Feeding' : feeder ? 'Ready' : 'Unknown'}</span>
              </div>
              <div className="actuator-meta-grid">
                <span><small>Feed count</small><strong>{feeder?.feed_count ?? '—'}</strong></span>
                <span><small>Last fed</small><strong>{feeder?.last_fed ?? '—'}</strong></span>
              </div>
              <button className="button button-primary" type="button" disabled={Boolean(busy)} onClick={() => setFeedConfirmOpen(true)}><Utensils size={15} /> Feed now</button>
              <div className="actuator-form-row">
                <label className="field"><span>Open angle (0–180°)</span><input type="number" min="0" max="180" step="1" value={feederAngle} onChange={(event) => setFeederAngle(event.target.value)} /></label>
                <label className="field"><span>Duration (500–60000 ms)</span><input type="number" min="500" max="60000" step="100" value={feederDuration} onChange={(event) => setFeederDuration(event.target.value)} /></label>
              </div>
              <button className="button button-secondary" type="button" disabled={Boolean(busy)} onClick={() => void queueCommand('feeder', 'config', { open_angle: Number(feederAngle), duration_ms: Number(feederDuration) }, 'Feeder configuration')}>Save feeder configuration</button>
              <div className="actuator-schedule">
                <div className="actuator-schedule-heading"><strong>Feeding schedule</strong><small>Three firmware slots</small></div>
                {feederSchedule.map((slot, index) => (
                  <div className="feeder-slot" key={index}>
                    <label className="toggle-label"><input type="checkbox" checked={slot.enabled} onChange={(event) => setFeederSchedule((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, enabled: event.target.checked } : item))} /> Slot {index + 1}</label>
                    <input aria-label={`Feeder slot ${index + 1} time`} type="time" value={slot.time} onChange={(event) => setFeederSchedule((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, time: event.target.value } : item))} />
                  </div>
                ))}
                <button className="button button-secondary" type="button" disabled={Boolean(busy)} onClick={() => void queueCommand('feeder', 'schedule', { slots: feederSchedule }, 'Feeder schedule')}>Save feeding schedule</button>
              </div>
            </article>
          </div>
          <section className="pump-test-section" aria-labelledby="pump-test-heading">
            <div className="pump-test-heading">
              <div>
                <p className="actuator-kicker">Controlled hardware test</p>
                <h3 id="pump-test-heading">Syringe pump manual tests</h3>
                <p>Empty-syringe or water-only checks for the registered device. No schedules or pH auto-dose controls are included.</p>
              </div>
            </div>
            <div className="pump-safety-warning" role="note">
              <AlertTriangle size={18} aria-hidden="true" />
              <span><strong>Manual test only — confirm physical setup first.</strong><small>Use empty syringes or water, keep both pumps clear of chemicals, and be ready to use Stop. The tester bridge must have <code>pump_manual_test_enabled: true</code> for these actions.</small></span>
            </div>
            <div className="pump-grid">
              <PumpCard
                actuator="pump_a"
                state={pumpA}
                durationMs={pumpADuration}
                onDurationChange={setPumpADuration}
                onDispense={() => setPumpConfirmation({ actuator: 'pump_a', action: 'dispense' })}
                onStop={() => void queueCommand('pump_a', 'stop', {}, 'Syringe Pump A stop', PUMP_COMMAND_EXPIRY_SECONDS)}
                onRetract={() => setPumpConfirmation({ actuator: 'pump_a', action: 'retract' })}
                busy={busy}
                disabled={pumpsDisabled}
              />
              <PumpCard
                actuator="pump_b"
                state={pumpB}
                durationMs={pumpBDuration}
                onDurationChange={setPumpBDuration}
                onDispense={() => setPumpConfirmation({ actuator: 'pump_b', action: 'dispense' })}
                onStop={() => void queueCommand('pump_b', 'stop', {}, 'Syringe Pump B stop', PUMP_COMMAND_EXPIRY_SECONDS)}
                onRetract={() => setPumpConfirmation({ actuator: 'pump_b', action: 'retract' })}
                busy={busy}
                disabled={pumpsDisabled}
              />
            </div>
          </section>
          <div className="actuator-history">
            <div className="actuator-history-heading">
              <div>
                <div className="actuator-history-title"><h3>Command history</h3><CommandHistoryTooltip /></div>
                <p>Admin command activity for this registered bridge</p>
              </div>
              <div className="actuator-history-heading-actions">
                {history.isFetching && !history.isLoading && <small className="actuator-history-updating">Updating…</small>}
                <button className="icon-button" type="button" aria-label="Refresh command history" onClick={() => void history.refetch()}>
                  <RefreshCw size={16} />
                </button>
                <Clock3 size={17} aria-hidden="true" />
              </div>
            </div>
            {historyData?.summary && (
              <div className="actuator-history-summary" aria-label="Command history summary">
                <span className="summary-total"><strong>{historyData.summary.total}</strong><small>Total</small></span>
                <span className="summary-queued"><strong>{historyData.summary.queued}</strong><small>Waiting</small></span>
                <span className="summary-executing"><strong>{historyData.summary.executing}</strong><small>Executing</small></span>
                <span className="summary-succeeded"><strong>{historyData.summary.succeeded}</strong><small>Succeeded</small></span>
                <span className="summary-failed"><strong>{historyData.summary.failed}</strong><small>Failed</small></span>
                <span className="summary-expired"><strong>{historyData.summary.expired}</strong><small>Expired</small></span>
              </div>
            )}
            <div className="actuator-history-filters">
              <label className="actuator-history-filter">
                <span>Actuator</span>
                <select
                  aria-label="Filter history by actuator"
                  value={historyActuator}
                  onChange={(event) => {
                    setHistoryActuator(event.target.value as HistoryActuatorFilter);
                    setHistoryPage(1);
                    setExpandedCommandId(null);
                  }}
                >
                  <option value="all">All actuators</option>
                  <option value="uv">UV light</option>
                  <option value="led">Normal LED light</option>
                  <option value="feeder">Fish feeder</option>
                  <option value="pump_a">Syringe Pump A</option>
                  <option value="pump_b">Syringe Pump B</option>
                </select>
              </label>
              <label className="actuator-history-filter">
                <span>Status</span>
                <select
                  aria-label="Filter history by status"
                  value={historyStatus}
                  onChange={(event) => {
                    setHistoryStatus(event.target.value as HistoryStatusFilter);
                    setHistoryPage(1);
                    setExpandedCommandId(null);
                  }}
                >
                  <option value="all">All statuses</option>
                  {Object.entries(commandStatusFilterLabel).map(([value, label]) => (
                    <option value={value} key={value}>{label}</option>
                  ))}
                </select>
              </label>
            </div>
            {history.isLoading ? <LoadingState label="Loading command history…" /> : history.isError ? <ErrorState message="Command history could not be loaded." retry={() => history.refetch()} /> : historyData?.items.length ? (
              <>
              <div className="actuator-history-list">
                {historyData.items.map((command) => {
                  const isExpanded = expandedCommandId === command.command_id;
                  const payloadSummary = formatPayloadSummary(command);
                  return (
                    <div className="actuator-history-row" key={command.command_id}>
                      <span className={`command-status command-${command.status}`}>
                        <span className="command-status-badges">
                          <StatusBadge value={command.status} />
                          {command.status === 'expired' && <span className="command-expired-badge">Never sent</span>}
                        </span>
                        <small className="command-status-detail">{commandStatusDescription[command.status]}</small>
                      </span>
                      <span className="actuator-history-action">
                        <strong>{formatCommandLabel(command)}</strong>
                        {payloadSummary && <small className="command-payload-summary">{payloadSummary}</small>}
                        <small>{command.actor_name ?? 'Administrator'} · {formatDate(command.requested_at)}</small>
                        <button
                          className="command-details-toggle"
                          type="button"
                          aria-expanded={isExpanded}
                          aria-controls={`command-details-${command.command_id}`}
                          onClick={() => setExpandedCommandId(isExpanded ? null : command.command_id)}
                        >
                          {isExpanded ? <ChevronUp size={14} aria-hidden="true" /> : <ChevronDown size={14} aria-hidden="true" />}
                          {isExpanded ? 'Hide details' : 'View details'}
                        </button>
                      </span>
                      <time dateTime={command.requested_at}>{relativeTime(command.requested_at)}</time>
                      {isExpanded && <CommandDetails command={command} />}
                    </div>
                  );
                })}
              </div>
              <div className="actuator-history-footer">
                <span aria-live="polite">Showing {historyStart}–{historyEnd} of {historyData.total}</span>
                <div className="actuator-history-pagination" aria-label="Command history pagination">
                  <button className="button button-secondary button-small" type="button" disabled={!historyData.has_previous || history.isFetching} onClick={() => { setExpandedCommandId(null); setHistoryPage((current) => Math.max(1, current - 1)); }}>
                    <ChevronLeft size={14} /> Previous
                  </button>
                  <span>Page {historyData.page} of {historyData.total_pages}</span>
                  <button className="button button-secondary button-small" type="button" disabled={!historyData.has_next || history.isFetching} onClick={() => { setExpandedCommandId(null); setHistoryPage((current) => current + 1); }}>
                    Next <ChevronRight size={14} />
                  </button>
                </div>
              </div>
              </>
            ) : historyData?.total ? (
              <EmptyState title="No commands on this page" message="Go back to the previous page to view newer actuator commands." />
            ) : historyActuator !== 'all' || historyStatus !== 'all' ? (
              <EmptyState title="No matching commands" message="Try a different actuator or status filter." />
            ) : <EmptyState title="No actuator commands yet" message="Queued commands and their bridge results will appear here." />}
          </div>
          </>
          )}
        </>
      )}
      <ConfirmDialog
        open={feedConfirmOpen}
        title="Feed this tank now?"
        message="This sends one manual feed command to the registered ESP32 feeder. Confirm the tank and feeder are ready before continuing."
        confirmLabel="Feed now"
        tone="primary"
        busy={busy === 'feeder:feed_now'}
        onConfirm={() => { setFeedConfirmOpen(false); void queueCommand('feeder', 'feed_now', {}, 'Manual feed'); }}
        onClose={() => setFeedConfirmOpen(false)}
      />
      <ConfirmDialog
        open={pumpConfirmation !== null}
        title={pumpConfirmation?.action === 'dispense' ? `Start ${confirmedPumpLabel} test?` : `Retract ${confirmedPumpLabel}?`}
        message={pumpConfirmation?.action === 'dispense'
          ? `Manual test only. This will start the ${confirmedPumpLabel} firmware dispense route for a maximum ${confirmedPumpDuration} ms before the bridge sends a safety stop. Confirm the syringe is empty or contains water and keep your hand near Stop.`
          : `This will call the ${confirmedPumpLabel} firmware retract route. Confirm the physical setup is safe and the pump is not handling chemicals.`}
        confirmLabel={pumpConfirmation?.action === 'dispense' ? 'Dispense / test' : 'Retract'}
        tone={pumpConfirmation?.action === 'dispense' ? 'primary' : 'danger'}
        busy={pumpConfirmation ? busy === `${pumpConfirmation.actuator}:${pumpConfirmation.action}` : false}
        onConfirm={() => {
          const confirmation = pumpConfirmation;
          if (!confirmation) return;
          setPumpConfirmation(null);
          const duration = confirmation.actuator === 'pump_a' ? pumpADuration : pumpBDuration;
          void queueCommand(
            confirmation.actuator,
            confirmation.action,
            confirmation.action === 'dispense' ? { duration_ms: Number(duration) } : {},
            `${actuatorLabels[confirmation.actuator]} ${confirmation.action === 'dispense' ? 'dispense/test' : 'retract'}`,
            PUMP_COMMAND_EXPIRY_SECONDS,
          );
        }}
        onClose={() => setPumpConfirmation(null)}
      />
      </Panel>
    </>
  );
}

export function StaffActuatorNotice() {
  return (
    <Panel title="Actuator controls" description="Restricted hardware actions">
      <div className="actuator-staff-notice"><LockKeyhole size={18} aria-hidden="true" /><span><strong>Administrator access required</strong><small>Staff accounts can monitor tank operations but cannot view or send actuator commands.</small></span></div>
    </Panel>
  );
}
