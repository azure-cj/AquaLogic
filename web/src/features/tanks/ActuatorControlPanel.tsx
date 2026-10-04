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
  PumpDispenseLock,
  PumpActuatorState,
} from '@/shared/api/models';
import {
  ConfirmDialog,
  EmptyState,
  ErrorState,
  LoadingState,
  Panel,
  CommandStatusBadge,
} from '@/shared/components/admin-ui';
import { notify } from '@/shared/lib/notify';
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

const defaultPumpSchedule: FeederScheduleSlot[] = [
  { enabled: false, time: '08:00' },
  { enabled: false, time: '14:00' },
  { enabled: false, time: '20:00' },
];

const HISTORY_PAGE_SIZE = 10;
const PUMP_COMMAND_EXPIRY_SECONDS = 20;
const PUMP_CONFIGURATION_EXPIRY_SECONDS = 120;

type HistoryActuatorFilter = 'all' | ActuatorName;
type HistoryStatusFilter = 'all' | ActuatorCommandStatus;
export type ActuatorControlPanelVariant = 'summary' | 'full';
type TooltipPosition = {
  top: number;
  left: number;
  arrowLeft: number;
  placement: 'top' | 'bottom';
};
type PumpConfirmation = { actuator: 'pump_a' | 'pump_b'; action: 'test_dispense' | 'retract' | 'refill_confirm' };
type PumpScheduleConfirmation = { actuator: 'pump_a' | 'pump_b'; slots: FeederScheduleSlot[] };

const commandStatusDescription: Record<ActuatorCommandStatus, string> = {
  queued: 'Waiting to be sent — no equipment action yet',
  executing: 'In progress — the equipment action may be underway',
  succeeded: 'Completed — the equipment confirmed the action',
  failed: 'Not completed — the equipment did not confirm the action',
  expired: 'Not sent — the request expired while waiting',
  outcome_unknown: 'Physical result unknown — verify the equipment before another dispense',
};

const commandStatusFilterLabel: Record<ActuatorCommandStatus, string> = {
  queued: 'Queued · waiting to send',
  executing: 'In progress · being processed',
  succeeded: 'Completed · action confirmed',
  failed: 'Failed · action not confirmed',
  expired: 'Expired · not sent',
  outcome_unknown: 'Outcome unknown · physical verification required',
};

const actuatorLabels: Record<ActuatorName, string> = {
  uv: 'UV light',
  led: 'Normal LED light',
  feeder: 'Fish feeder',
  pump_a: 'pH Up Syringe Pump',
  pump_b: 'pH Down Syringe Pump',
};

const actionLabels: Record<ActuatorAction, string> = {
  on: 'Turn on',
  off: 'Turn off',
  timer: 'Run timer',
  schedule: 'Update schedule',
  feed_now: 'Feed now',
  config: 'Update configuration',
  dispense: 'Dispense',
  test_dispense: 'Manual dispense',
  refill_confirm: 'Confirm syringe refill',
  stop: 'Stop',
  retract: 'Retract',
};

const PUMP_TIME_ZONE = 'Asia/Manila';
const pumpTimestampPattern = /^(\d{4})-(\d{2})-(\d{2})T([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d)(?:\.\d+)?)?(Z|[+-](?:0\d|1\d|2[0-3]):[0-5]\d)$/i;
const manilaCalendarDate = new Intl.DateTimeFormat('en-CA', {
  timeZone: PUMP_TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});
const manilaClockTime = new Intl.DateTimeFormat('en-PH', {
  timeZone: PUMP_TIME_ZONE,
  hour: 'numeric',
  minute: '2-digit',
});

function parsePumpTimestamp(value?: string | null) {
  if (!value) return null;
  const match = pumpTimestampPattern.exec(value.trim());
  if (!match) return null;

  const [, yearValue, monthValue, dayValue, , , , timeZone] = match;
  const year = Number(yearValue);
  const month = Number(monthValue);
  const day = Number(dayValue);
  const calendarDate = new Date(Date.UTC(year, month - 1, day));
  if (
    month < 1 || month > 12 ||
    calendarDate.getUTCFullYear() !== year ||
    calendarDate.getUTCMonth() !== month - 1 ||
    calendarDate.getUTCDate() !== day
  ) return null;
  if (timeZone.toUpperCase() !== 'Z') {
    const offsetHours = Number(timeZone.slice(1, 3));
    const offsetMinutes = Number(timeZone.slice(4, 6));
    if (offsetHours > 23 || offsetMinutes > 59) return null;
  }

  const timestamp = new Date(value);
  return Number.isNaN(timestamp.getTime()) ? null : timestamp;
}

function manilaDateKey(value: Date) {
  return manilaCalendarDate.formatToParts(value)
    .filter((part) => part.type === 'year' || part.type === 'month' || part.type === 'day')
    .map((part) => part.value)
    .join('-');
}

export function formatPumpTimestamp(value?: string | null, fallback = 'Time unavailable') {
  const timestamp = parsePumpTimestamp(value);
  if (!timestamp) return fallback;
  if (manilaDateKey(timestamp) === manilaDateKey(new Date())) {
    return `Today, ${manilaClockTime.format(timestamp)}`;
  }
  return formatDate(value);
}

export function formatLastDispensed(value?: string | null) {
  const normalized = value?.trim() ?? '';
  if (!normalized || /^never$/i.test(normalized)) return 'No dispense yet';
  if (/^time not synchronized$/i.test(normalized)) return 'Device time not synced';

  const formatted = formatPumpTimestamp(normalized, '');
  if (formatted) return formatted;

  const timeOnly = /^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/.test(normalized);
  if (timeOnly) {
    const [hours, minutes] = normalized.split(':').map(Number);
    const referenceTime = new Date(Date.UTC(2000, 0, 1, hours, minutes));
    return `${new Intl.DateTimeFormat('en-PH', {
      timeZone: 'UTC',
      hour: 'numeric',
      minute: '2-digit',
    }).format(referenceTime)} (date unavailable)`;
  }
  return 'Time unavailable';
}

export function formatCooldownClearsAt(value?: string | null, clockSynced?: boolean | null) {
  if (clockSynced === false) return 'Unavailable until device time syncs';
  const normalized = value?.trim() ?? '';
  if (/^(?:available|eligible)\s+now$/i.test(normalized) || /^now$/i.test(normalized)) return 'Available now';
  const timestamp = parsePumpTimestamp(normalized);
  if (!timestamp) return 'Unavailable';
  if (timestamp.getTime() <= Date.now()) return 'Available now';
  return formatPumpTimestamp(normalized, 'Unavailable');
}

export function formatNextScheduledDose(
  value?: string | null,
  clockSynced?: boolean | null,
  schedule?: FeederScheduleSlot[] | null,
) {
  const hasEnabledTime = schedule?.some((slot) => slot.enabled);
  if (hasEnabledTime === false) return 'No enabled dose time';
  if (clockSynced === false) return 'Unavailable until device time syncs';
  return formatPumpTimestamp(value, hasEnabledTime ? 'Unavailable' : 'Schedule time unavailable');
}

type PumpScheduleEventCopy = { message: string; detail?: string };

export function formatPumpScheduleEvent(event: string): PumpScheduleEventCopy {
  const normalized = event.trim();
  if (/skipped:.*(?:two-hour|cooldown|minimum interval)/i.test(normalized)) {
    return { message: 'Scheduled dose skipped because the two-hour minimum interval has not passed.' };
  }
  if (/skipped:.*(?:could not persist occurrence|persistent safety state|could not persist pump safety state)/i.test(normalized)) {
    return { message: 'Scheduled dose skipped because the equipment status could not be verified.' };
  }
  if (/skipped:.*(?:insufficient volume|check syringe|refill confirmation|syringe contents)/i.test(normalized)) {
    return { message: 'Scheduled dose skipped because the syringe needs to be checked and refilled if needed.' };
  }
  if (/skipped:.*(?:pump is already active|pump could not start|a pump is already active)/i.test(normalized)) {
    return { message: 'Scheduled dose skipped because a pump was already running.' };
  }
  if (/skipped:.*(?:time sync|ntp)/i.test(normalized)) {
    return { message: 'Scheduled dose skipped because device time is not synced.' };
  }
  if (/scheduled .+ dose started at /i.test(normalized)) {
    return { message: 'A scheduled dose has started. Pump movement is underway.' };
  }
  return {
    message: 'A pump schedule update needs attention. Review the pump status before continuing.',
    detail: normalized,
  };
}

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
    return 'Run the configured chemical dose';
  }
  if (command.action === 'test_dispense') {
    return 'Manual water-only dispense cycle';
  }
  if (command.action === 'refill_confirm') {
    return 'Confirm the syringe was physically refilled';
  }
  if (command.action === 'config') {
    const angle = typeof payload.open_angle === 'number' ? `${payload.open_angle} degrees` : 'configured angle';
    const duration = formatDuration(payload.duration_ms) ?? 'configured duration';
    return `Open ${angle} for ${duration}`;
  }
  if (command.action === 'schedule' && (command.actuator === 'pump_a' || command.actuator === 'pump_b')) {
    const slots = Array.isArray(payload.slots) ? payload.slots : [];
    const enabledSlots = slots.filter((slot) => typeof slot === 'object' && slot !== null && 'enabled' in slot && slot.enabled).length;
    return `${enabledSlots} of 3 chemical dose times enabled`;
  }
  if (command.action === 'schedule' && (command.actuator === 'uv' || command.actuator === 'led')) {
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
      This history shows administrator actions for this tank. Queued means waiting to be sent; Completed means the equipment confirmed the action; Expired means it was not sent before the request window closed.
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
        <div><dt>Processing started</dt><dd>{command.executing_at ? formatDate(command.executing_at) : 'Not started'}</dd></div>
        <div><dt>Equipment result</dt><dd>{command.execution_at ? formatDate(command.execution_at) : command.outcome_unknown_at ? `Unknown since ${formatDate(command.outcome_unknown_at)}` : 'Not reported'}</dd></div>
        <div><dt>Actor</dt><dd>{command.actor_name ?? 'Administrator'}</dd></div>
      </dl>
      {payloadSummary && <p className="command-details-summary"><strong>Validated request</strong><span>{payloadSummary}</span></p>}
      {command.status === 'outcome_unknown' && <p className="command-details-error"><strong>Physical verification required</strong><span>This command may have reached the equipment. Verification clears the software pump lock but does not prove the historical dose.</span></p>}
      {command.error && <p className="command-details-error"><strong>Reported failure</strong><span>{command.error}</span></p>}
      {command.result && <p className="command-details-result"><strong>Completion result</strong><span>The equipment action was reported as complete.</span></p>}
      {command.physical_verification_at && <p className="command-details-result"><strong>Verified by {command.physical_verification_actor_name ?? 'Administrator'}</strong><span>{formatDate(command.physical_verification_at)}{command.physical_verification_note ? ` · ${command.physical_verification_note}` : ''}</span></p>}
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
      {busyFor('on') && <small className="actuator-busy">Preparing request…</small>}
    </article>
  );
}

function PumpCard({
  actuator,
  state,
  schedule,
  onScheduleChange,
  onSaveSchedule,
  onDispense,
  onStop,
  onRetract,
  onRefill,
  busy,
  disabled,
  lock,
  onClearVerification,
}: {
  actuator: 'pump_a' | 'pump_b';
  state: PumpActuatorState | null;
  schedule: FeederScheduleSlot[];
  onScheduleChange: (schedule: FeederScheduleSlot[]) => void;
  onSaveSchedule: () => void;
  onDispense: () => void;
  onStop: () => void;
  onRetract: () => void;
  onRefill: () => void;
  busy: string | null;
  disabled: boolean;
  lock: PumpDispenseLock | undefined;
  onClearVerification: () => void;
}) {
  const label = actuatorLabels[actuator];
  const busyFor = (action: string) => busy === `${actuator}:${action}`;
  const remaining = state?.volume_known === false
    ? 'Fill not confirmed'
    : state?.remaining_ml !== undefined && state?.remaining_ml !== null
      ? `${state.remaining_ml.toFixed(2)} mL of ${(state.capacity_ml ?? 5).toFixed(2)} mL`
      : 'Unavailable';
  return (
    <article className="actuator-card pump-card">
      <div className="actuator-card-header">
        <div>
          <h3>{label}</h3>
        </div>
        <span className={`actuator-state ${state?.active ? 'is-on' : state ? 'is-off' : 'is-unknown'}`}>
          <Power size={14} aria-hidden="true" />
          {state ? (state.active ? 'Running' : 'Idle') : 'Unknown'}
        </span>
      </div>
      <div className="actuator-meta-grid">
        <span><small>Dispense count</small><strong>{state?.dose_count ?? '—'}</strong></span>
        <span><small>Dose volume</small><strong>{state ? `${state.volume_ml.toFixed(2)} mL` : '—'}</strong></span>
        <span><small>Last dispense</small><strong>{formatLastDispensed(state?.last_dispensed)}</strong></span>
        <span><small>Estimated remaining</small><strong>{remaining}</strong></span>
        <span><small>Fill check</small><strong>{state?.refill_required ? 'Confirmation needed' : state?.volume_known ? 'Confirmed' : 'Unavailable'}</strong></span>
        <span><small>Schedule time</small><strong>{state?.clock_synced ? 'Synced · Manila time' : state?.clock_synced === false ? 'Not synced — dosing paused' : 'Unavailable'}</strong></span>
        <span><small>Cooldown clears</small><strong>{formatCooldownClearsAt(state?.next_eligible_at, state?.clock_synced)}</strong></span>
        <span><small>Next scheduled dose</small><strong>{formatNextScheduledDose(state?.next_dose_at, state?.clock_synced, state?.schedule)}</strong></span>
      </div>
      <div className="pump-configured-dose">
        <span><strong>Dose volume</strong><small>Each scheduled dose uses this volume.</small></span>
        <strong>{state ? `${state.volume_ml.toFixed(2)} mL` : 'Unavailable'}</strong>
      </div>
      <div className="pump-action-grid" aria-label={`${label} pump controls`}>
        <button className="button button-primary" type="button" aria-label={`${label} manual dispense`} disabled={disabled || Boolean(busy) || Boolean(lock) || state?.refill_required === true} onClick={onDispense}>
          <Play size={15} /> Manual dispense
        </button>
        <button className="button button-danger pump-stop-button" type="button" aria-label={`${label} stop`} disabled={disabled || (Boolean(busy) && !lock)} onClick={onStop}>
          <Square size={14} /> Stop
        </button>
        <button className="button button-secondary" type="button" aria-label={`${label} retract`} disabled={disabled || Boolean(busy)} onClick={onRetract}>
          <RotateCcw size={15} /> Retract
        </button>
        <button className="button button-secondary" type="button" aria-label={`${label} confirm refill`} disabled={disabled || Boolean(busy) || Boolean(lock)} onClick={onRefill}>
          Confirm refill
        </button>
      </div>
      <div className="actuator-schedule pump-schedule">
        <div className="actuator-schedule-heading"><strong>Dosing schedule</strong><small>Uses Manila time (Asia/Manila). Set up to three daily doses. Doses that cannot run are skipped and not rescheduled.</small></div>
        {schedule.map((slot, index) => (
          <div className="feeder-slot" key={index}>
            <label className="toggle-label"><input type="checkbox" checked={slot.enabled} disabled={disabled || Boolean(busy)} onChange={(event) => onScheduleChange(schedule.map((item, itemIndex) => itemIndex === index ? { ...item, enabled: event.target.checked } : item))} /> Dose time {index + 1}</label>
            <input aria-label={`${label} dose time ${index + 1}`} type="time" value={slot.time} disabled={disabled || Boolean(busy)} onChange={(event) => onScheduleChange(schedule.map((item, itemIndex) => itemIndex === index ? { ...item, time: event.target.value } : item))} />
          </div>
        ))}
        <button className="button button-secondary" type="button" disabled={disabled || Boolean(busy)} onClick={onSaveSchedule}>Save dosing schedule</button>
      </div>
      {state?.schedule_event && (() => {
        const eventCopy = formatPumpScheduleEvent(state.schedule_event);
        return (
          <div className="pump-uncertainty-note" role="status">
            <strong>{eventCopy.message}</strong>
            {eventCopy.detail && <details><summary>Device message</summary><small>{eventCopy.detail}</small></details>}
          </div>
        );
      })()}
      {state?.refill_required && <small className="pump-disabled-note">Dosing is paused until you check and confirm the syringe fill. Refill it if needed.</small>}
      {state?.clock_synced === false && <small className="pump-disabled-note">Scheduled and chemical dosing are paused until the device time is synced.</small>}
      {lock?.status === 'executing' && <small className="pump-uncertainty-note">A previous dispense is awaiting equipment confirmation. Do not start another dispense.</small>}
      {lock?.status === 'outcome_unknown' && (
        <div className="pump-uncertainty-note" role="status">
          <strong>The previous dispense may have happened. Check the pump in person before another dispense.</strong>
          <small>Stop remains available while the equipment connection is online. Recording this check only clears the software lock; it does not prove how much was previously dispensed.</small>
          <button className="button button-secondary button-small" type="button" onClick={onClearVerification}>Record pump check</button>
        </div>
      )}
      {disabled && <small className="pump-disabled-note">Reconnect the equipment before dispensing. Offline pump actions are not queued.</small>}
      {busyFor('test_dispense') && <small className="actuator-busy">Preparing manual dispense…</small>}
      {busyFor('schedule') && <small className="actuator-busy">Saving dosing schedule…</small>}
    </article>
  );
}

function BridgeOfflineWarning({ freshness }: { freshness?: DeviceActuatorStatus['device_freshness']; }) {
  return (
    <div className="actuator-offline-warning" role="status">
      <AlertTriangle size={17} aria-hidden="true" />
      <span>
        <strong>Equipment connection is {freshness === 'unknown' ? 'not reporting' : 'offline or stale'}</strong>
        <small>Light and feeder requests may expire while waiting. Pump controls are available when the equipment is online.</small>
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
  const pumpStatus = (state: PumpActuatorState | null) => state ? (state.active ? 'Running' : 'Idle') : 'Unknown';
  return (
    <article className="actuator-summary-card actuator-summary-pumps">
      <div className="actuator-summary-card-header">
        <div>
          <p className="actuator-kicker">Pump controls</p>
          <h3>Syringe pumps</h3>
        </div>
      </div>
      <div className="actuator-summary-pump-list">
        <span><strong>pH Up</strong><small>Pump A · {pumpStatus(pumpA)}</small></span>
        <span><strong>pH Down</strong><small>Pump B · {pumpStatus(pumpB)}</small></span>
      </div>
      <p className="actuator-summary-detail">Review pump status, syringe levels, and dosing schedules.</p>
      <Link className="text-link" to={`/admin/tanks/${tankId}/actuators`}>Open pump controls <ArrowRight size={14} /></Link>
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

export function ActuatorControlPanel({ tankId, tankName, variant = 'full', readOnly = false }: { tankId: number; tankName?: string; variant?: ActuatorControlPanelVariant; readOnly?: boolean }) {
  const fullView = variant === 'full';
  const queryClient = useQueryClient();
  const [busy, setBusy] = useState<string | null>(null);
  const [feedConfirmOpen, setFeedConfirmOpen] = useState(false);
  const [pumpConfirmation, setPumpConfirmation] = useState<PumpConfirmation | null>(null);
  const [pumpScheduleConfirmation, setPumpScheduleConfirmation] = useState<PumpScheduleConfirmation | null>(null);
  const [verificationLock, setVerificationLock] = useState<PumpDispenseLock | null>(null);
  const [historyPage, setHistoryPage] = useState(1);
  const [historyActuator, setHistoryActuator] = useState<HistoryActuatorFilter>('all');
  const [historyStatus, setHistoryStatus] = useState<HistoryStatusFilter>('all');
  const [expandedCommandId, setExpandedCommandId] = useState<string | null>(null);
  const [uvSchedule, setUvSchedule] = useState<LightScheduleForm>(defaultSchedule);
  const [ledSchedule, setLedSchedule] = useState<LightScheduleForm>(defaultSchedule);
  const [feederSchedule, setFeederSchedule] = useState<FeederScheduleSlot[]>(defaultFeederSchedule);
  const [pumpASchedule, setPumpASchedule] = useState<FeederScheduleSlot[]>(defaultPumpSchedule);
  const [pumpBSchedule, setPumpBSchedule] = useState<FeederScheduleSlot[]>(defaultPumpSchedule.map((slot) => ({ ...slot })));
  const [uvTimer, setUvTimer] = useState('10');
  const [ledTimer, setLedTimer] = useState('10');
  const [feederAngle, setFeederAngle] = useState('125');
  const [feederDuration, setFeederDuration] = useState('1000');
  const [scheduleInitialized, setScheduleInitialized] = useState(false);
  const lastPumpScheduleEvents = useRef<Record<string, string>>({});

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
    setPumpConfirmation(null);
    setPumpScheduleConfirmation(null);
    setVerificationLock(null);
    setScheduleInitialized(false);
  }, [tankId]);

  useEffect(() => {
    if (scheduleInitialized || !status.data) return;
    const uv = asLightState(status.data.actuators.find((item) => item.actuator === 'uv'));
    const led = asLightState(status.data.actuators.find((item) => item.actuator === 'led'));
    const feeder = asFeederState(status.data.actuators.find((item) => item.actuator === 'feeder'));
    const pumpA = asPumpState(status.data.actuators.find((item) => item.actuator === 'pump_a'));
    const pumpB = asPumpState(status.data.actuators.find((item) => item.actuator === 'pump_b'));
    if (uv) setUvSchedule({ enabled: uv.schedule_enabled, on_time: uv.on_time, off_time: uv.off_time });
    if (led) setLedSchedule({ enabled: led.schedule_enabled, on_time: led.on_time, off_time: led.off_time });
    if (feeder) {
      setFeederAngle(String(feeder.open_angle));
      setFeederDuration(String(feeder.duration_ms));
      setFeederSchedule(feeder.schedule);
    }
    if (pumpA?.schedule) setPumpASchedule(pumpA.schedule);
    if (pumpB?.schedule) setPumpBSchedule(pumpB.schedule);
    setScheduleInitialized(true);
  }, [scheduleInitialized, status.data]);

  useEffect(() => {
    if (!status.data) return;
    for (const actuator of ['pump_a', 'pump_b'] as const) {
      const pump = asPumpState(status.data.actuators.find((item) => item.actuator === actuator));
      const event = pump?.schedule_event ?? '';
      const previous = lastPumpScheduleEvents.current[actuator];
      if (previous !== undefined && event && event !== previous) {
        notify.error(formatPumpScheduleEvent(event).message);
      }
      lastPumpScheduleEvents.current[actuator] = event;
    }
  }, [status.data]);

  const queueCommand = async (
    actuator: ActuatorName,
    action: ActuatorAction,
    payload: Record<string, unknown>,
    label: string,
    expiresInSeconds?: number,
  ) => {
    if (readOnly) return;
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
      notify.success(`${label} request queued. The system will update its status after processing.`);
    } catch (caught) {
      notify.error(errorMessage(caught, `Could not queue the ${label.toLowerCase()} command.`));
    } finally {
      setBusy(null);
    }
  };

  const savePumpSchedule = (actuator: 'pump_a' | 'pump_b', slots: FeederScheduleSlot[]) => {
    if (readOnly) return;
    const enabled = slots.some((slot) => slot.enabled);
    if (enabled) {
      const state = asPumpState(status.data?.actuators.find((item) => item.actuator === actuator));
      if (!state || state.volume_known !== true || state.refill_required) {
        notify.error('Check the syringe, refill it if needed, and confirm its fill before enabling the dosing schedule.');
        return;
      }
      setPumpScheduleConfirmation({ actuator, slots });
      return;
    }
    void queueCommand(actuator, 'schedule', { slots }, `${actuatorLabels[actuator]} dosing schedule`, PUMP_CONFIGURATION_EXPIRY_SECONDS);
  };

  const clearUncertainty = async () => {
    if (readOnly || !verificationLock) return;
    const key = `clear:${verificationLock.command_id}`;
    setBusy(key);
    try {
      await api<ActuatorCommand>(`/tanks/${tankId}/actuators/commands/${verificationLock.command_id}/clear-uncertainty`, {
        method: 'POST',
        body: JSON.stringify({}),
      });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['tank-actuator-status', tankId] }),
        queryClient.invalidateQueries({ queryKey: ['tank-actuator-history', tankId] }),
      ]);
      setVerificationLock(null);
      notify.success('Pump check recorded. The historical command remains Outcome unknown; the software lock is cleared, and the amount previously dispensed is still unknown.');
    } catch (caught) {
      notify.error(errorMessage(caught, 'Could not record the pump check.'));
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
  const pumpALock = status.data?.pump_dispense_locks?.find((lock) => lock.actuator === 'pump_a');
  const pumpBLock = status.data?.pump_dispense_locks?.find((lock) => lock.actuator === 'pump_b');
  const confirmedPumpLabel = pumpConfirmation ? actuatorLabels[pumpConfirmation.actuator] : '';
  const confirmedPumpVolume = pumpConfirmation?.actuator === 'pump_a' ? pumpA?.volume_ml : pumpB?.volume_ml;
  const confirmedPump = pumpConfirmation?.actuator === 'pump_a' ? pumpA : pumpB;
  const confirmedPumpNextEligible = formatCooldownClearsAt(confirmedPump?.next_eligible_at, confirmedPump?.clock_synced);

  return (
    <>
      <Panel
        title={readOnly ? 'Equipment history' : fullView ? 'Equipment controls' : 'Equipment snapshot'}
        description={readOnly ? 'Retained administrator command history; retired equipment is read-only' : fullView ? 'Administrator-only equipment controls for this tank' : 'Quick equipment controls for this tank'}
        className={`tank-actuator-panel ${fullView ? '' : 'tank-actuator-summary-panel'} ${readOnly ? 'retired-read-only' : ''}`}
        action={fullView && !readOnly ? (
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
        <LoadingState label="Loading equipment state…" />
      ) : status.isError ? (
        <ErrorState message="Equipment state could not be loaded. No control action was sent." retry={() => status.refetch()} />
      ) : (
        <>
          <div className="bridge-device-summary">
            <span><small>Equipment status</small><strong>{status.data?.device_online ? 'Online' : 'Offline / stale'}</strong></span>
            <span><small>Connection freshness</small><strong>{status.data?.device_online ? 'Up to date' : 'Needs attention'}</strong></span>
            <span><small>Last update</small><strong>{relativeTime(status.data?.last_seen_at)}</strong></span>
            <button className="icon-button" type="button" aria-label="Refresh equipment status" onClick={() => void status.refetch()}><RefreshCw size={16} /></button>
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
          <div className="actuator-grid" hidden={readOnly}>
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
                <div className="actuator-schedule-heading"><strong>Feeding schedule</strong><small>Up to 3 daily times</small></div>
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
          <section className="pump-test-section" aria-labelledby="pump-controls-heading" hidden={readOnly}>
            <div className="pump-test-heading">
              <div>
                <h3 id="pump-controls-heading">Pump controls</h3>
                <p>Manage dosing schedules and review syringe levels.</p>
              </div>
            </div>
            <div className="pump-grid">
              <PumpCard
                actuator="pump_a"
                state={pumpA}
                schedule={pumpASchedule}
                onScheduleChange={setPumpASchedule}
                onSaveSchedule={() => savePumpSchedule('pump_a', pumpASchedule)}
                onDispense={() => setPumpConfirmation({ actuator: 'pump_a', action: 'test_dispense' })}
                onStop={() => void queueCommand('pump_a', 'stop', {}, `${actuatorLabels.pump_a} stop`, PUMP_COMMAND_EXPIRY_SECONDS)}
                onRetract={() => setPumpConfirmation({ actuator: 'pump_a', action: 'retract' })}
                onRefill={() => setPumpConfirmation({ actuator: 'pump_a', action: 'refill_confirm' })}
                busy={busy}
                disabled={pumpsDisabled}
                lock={pumpALock}
                onClearVerification={() => setVerificationLock(pumpALock ?? null)}
              />
              <PumpCard
                actuator="pump_b"
                state={pumpB}
                schedule={pumpBSchedule}
                onScheduleChange={setPumpBSchedule}
                onSaveSchedule={() => savePumpSchedule('pump_b', pumpBSchedule)}
                onDispense={() => setPumpConfirmation({ actuator: 'pump_b', action: 'test_dispense' })}
                onStop={() => void queueCommand('pump_b', 'stop', {}, `${actuatorLabels.pump_b} stop`, PUMP_COMMAND_EXPIRY_SECONDS)}
                onRetract={() => setPumpConfirmation({ actuator: 'pump_b', action: 'retract' })}
                onRefill={() => setPumpConfirmation({ actuator: 'pump_b', action: 'refill_confirm' })}
                busy={busy}
                disabled={pumpsDisabled}
                lock={pumpBLock}
                onClearVerification={() => setVerificationLock(pumpBLock ?? null)}
              />
            </div>
          </section>
          <div className="actuator-history">
            <div className="actuator-history-heading">
              <div>
                <div className="actuator-history-title"><h3>Command history</h3><CommandHistoryTooltip /></div>
                <p>Recent administrator activity for this tank</p>
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
                <span className="summary-unknown"><strong>{historyData.summary.outcome_unknown}</strong><small>Outcome unknown</small></span>
              </div>
            )}
            <div className="actuator-history-filters">
              <label className="actuator-history-filter">
                <span>Equipment</span>
                <select
                  aria-label="Filter history by equipment"
                  value={historyActuator}
                  onChange={(event) => {
                    setHistoryActuator(event.target.value as HistoryActuatorFilter);
                    setHistoryPage(1);
                    setExpandedCommandId(null);
                  }}
                >
                  <option value="all">All equipment</option>
                  <option value="uv">UV light</option>
                  <option value="led">Normal LED light</option>
                  <option value="feeder">Fish feeder</option>
                  <option value="pump_a">pH Up Syringe Pump</option>
                  <option value="pump_b">pH Down Syringe Pump</option>
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
                          <CommandStatusBadge status={command.status} />
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
              <EmptyState title="No requests on this page" message="Go back to the previous page to view newer equipment activity." />
            ) : historyActuator !== 'all' || historyStatus !== 'all' ? (
              <EmptyState title="No matching activity" message="Try different equipment or status filters." />
            ) : <EmptyState title="No equipment activity yet" message="Equipment requests and their results will appear here." />}
          </div>
          </>
          )}
        </>
      )}
      <ConfirmDialog
        open={feedConfirmOpen}
        title="Feed this tank now?"
        message="This sends one manual feed request for this tank. Confirm the tank and feeder are ready before continuing."
        confirmLabel="Feed now"
        tone="primary"
        busy={busy === 'feeder:feed_now'}
        onConfirm={() => { setFeedConfirmOpen(false); void queueCommand('feeder', 'feed_now', {}, 'Manual feed'); }}
        onClose={() => setFeedConfirmOpen(false)}
      />
      <ConfirmDialog
        open={pumpConfirmation !== null}
        title={pumpConfirmation?.action === 'test_dispense'
          ? `Start a manual dispense cycle for ${confirmedPumpLabel}?`
          : pumpConfirmation?.action === 'refill_confirm'
            ? `Confirm ${confirmedPumpLabel} refill?`
            : `Retract ${confirmedPumpLabel}?`}
        message={pumpConfirmation?.action === 'test_dispense'
          ? `Tank: ${tankName ?? `Tank ${tankId}`}. Equipment: ${status.data?.device_online ? 'Online' : 'Offline'}. This runs one preset pump cycle${confirmedPumpVolume !== undefined ? ` (${confirmedPumpVolume.toFixed(2)} mL)` : ''}. Use water or an empty syringe only; do not use chemicals. Estimated remaining volume may change. This cycle does not start the chemical-dose cooldown. Stay beside the equipment and be ready to press Stop. If you are unsure whether it completed, check the pump before starting another cycle.`
          : pumpConfirmation?.action === 'refill_confirm'
            ? `Physically check the syringe and refill it to ${(pumpConfirmation.actuator === 'pump_a' ? pumpA?.capacity_ml : pumpB?.capacity_ml ?? 5)?.toFixed(2) ?? '5.00'} mL if needed before confirming. This updates the estimated amount remaining only; it does not move the motor or reset the two-hour cooldown. Cooldown clears: ${confirmedPumpNextEligible}.`
            : `Tank: ${tankName ?? `Tank ${tankId}`}. Equipment: ${status.data?.device_online ? 'Online' : 'Offline'}. This starts the ${confirmedPumpLabel} retract motor action. It does not update the volume estimate. Check the pump setup and keep Stop available.`}
        confirmLabel={pumpConfirmation?.action === 'test_dispense' ? 'Run manual cycle' : pumpConfirmation?.action === 'refill_confirm' ? 'Confirm refill' : 'Retract'}
        tone={pumpConfirmation?.action === 'retract' ? 'danger' : 'primary'}
        busy={pumpConfirmation ? busy === `${pumpConfirmation.actuator}:${pumpConfirmation.action}` : false}
        onConfirm={() => {
          const confirmation = pumpConfirmation;
          if (!confirmation) return;
          setPumpConfirmation(null);
          void queueCommand(
            confirmation.actuator,
            confirmation.action,
            {},
            `${actuatorLabels[confirmation.actuator]} ${confirmation.action === 'test_dispense' ? 'manual dispense' : confirmation.action === 'refill_confirm' ? 'refill confirmation' : 'retract'}`,
            confirmation.action === 'refill_confirm' ? PUMP_CONFIGURATION_EXPIRY_SECONDS : PUMP_COMMAND_EXPIRY_SECONDS,
          );
        }}
        onClose={() => setPumpConfirmation(null)}
      />
      <ConfirmDialog
        open={pumpScheduleConfirmation !== null}
        title={`Save the dosing schedule for ${pumpScheduleConfirmation ? actuatorLabels[pumpScheduleConfirmation.actuator] : 'pump'}?`}
        message={pumpScheduleConfirmation ? `This sets the pump to dispense ${((pumpScheduleConfirmation.actuator === 'pump_a' ? pumpA?.volume_ml : pumpB?.volume_ml) ?? 0).toFixed(2)} mL at ${pumpScheduleConfirmation.slots.filter((slot) => slot.enabled).map((slot) => slot.time).join(', ')} Manila time. Doses follow this schedule and are not triggered by pH. Confirm the syringe contains the intended liquid and enough volume. Both pumps share a two-hour minimum interval. If a dose cannot run, it is skipped and not rescheduled.` : ''}
        confirmLabel="Save schedule"
        tone="danger"
        busy={pumpScheduleConfirmation ? busy === `${pumpScheduleConfirmation.actuator}:schedule` : false}
        onConfirm={() => {
          const confirmation = pumpScheduleConfirmation;
          if (!confirmation) return;
          setPumpScheduleConfirmation(null);
          void queueCommand(
            confirmation.actuator,
            'schedule',
            { slots: confirmation.slots },
            `${actuatorLabels[confirmation.actuator]} dosing schedule`,
            PUMP_CONFIGURATION_EXPIRY_SECONDS,
          );
        }}
        onClose={() => setPumpScheduleConfirmation(null)}
      />
      <ConfirmDialog
        open={verificationLock !== null}
        title="Record pump check?"
        message="Confirm that you inspected this pump before another dispense. This records who completed the check and clears only the software lock; it does not prove how much liquid was previously dispensed. The historical command remains Outcome unknown."
        confirmLabel="Record pump check"
        tone="danger"
        busy={verificationLock ? busy === `clear:${verificationLock.command_id}` : false}
        onConfirm={() => void clearUncertainty()}
        onClose={() => setVerificationLock(null)}
      />
      </Panel>
    </>
  );
}

export function StaffActuatorNotice() {
  return (
    <Panel title="Equipment controls" description="Administrator-only equipment controls">
      <div className="actuator-staff-notice"><LockKeyhole size={18} aria-hidden="true" /><span><strong>Administrator access required</strong><small>Staff accounts can monitor tank operations but cannot use equipment controls.</small></span></div>
    </Panel>
  );
}
