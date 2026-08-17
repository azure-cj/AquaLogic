import type { FleetStatus } from '@/shared/components/admin-ui';
import type { Reading } from './client';

export type Tank = {
  id: number;
  public_id: string;
  name: string;
  location: string;
  public_location?: string | null;
  description?: string | null;
  is_public: boolean;
  customer_id?: number | null;
  customer?: { id: number; name: string; } | null;
  feeding_schedule?: string | null;
  public_care_notes?: string | null;
  fish_species?: Fish[];
  tank_code?: string | null;
  habitat_label?: string | null;
  water_type?: 'freshwater' | 'saltwater' | 'brackish' | null;
  volume_liters?: number | null;
  established_on?: string | null;
  hero_image_url?: string | null;
};

export type Fish = {
  id: number;
  common_name: string;
  scientific_name: string;
  category: string;
  photo_url?: string | null;
  description?: string | null;
  diet_type?: 'Carnivore' | 'Omnivore' | 'Herbivore' | null;
  diet?: string | null;
  compatibility_notes?: string | null;
  care_tips?: string | null;
  tank_count: number;
};

export type Alert = {
  id: number;
  tank_id: number;
  parameter: string;
  severity: 'warning' | 'critical';
  message: string;
  is_resolved: boolean;
  created_at: string;
  resolved_at?: string | null;
};

export type Customer = {
  id: number;
  name: string;
  email?: string | null;
  phone?: string | null;
  notes?: string | null;
  is_active: boolean;
};

export type FleetTank = {
  id: number;
  public_id: string;
  name: string;
  location: string;
  customer: { id: number; name: string; } | null;
  latest_reading: Reading | null;
  status: FleetStatus;
  last_reading_at: string | null;
  reporting_age_seconds: number | null;
  active_warning_count: number;
  active_critical_count: number;
  species_care_status?: SpeciesSuitabilityStatus;
  assigned_species_count?: number;
};

export type TankOperations = {
  tank_id: number;
  evaluated_at: string;
  status: FleetStatus;
  latest_reading: Reading | null;
  parameter_statuses: Record<string, FleetStatus | 'unavailable'>;
  active_alerts: Alert[];
};

export type ActuatorName = 'uv' | 'led' | 'feeder' | 'pump_a' | 'pump_b';
export type ActuatorAction = 'on' | 'off' | 'timer' | 'schedule' | 'feed_now' | 'config' | 'dispense' | 'stop' | 'retract';
export type ActuatorCommandStatus = 'queued' | 'executing' | 'succeeded' | 'failed' | 'expired';

export type LightActuatorState = {
  on: boolean;
  remaining_ms: number;
  total_on_ms: number;
  schedule_enabled: boolean;
  on_time: string;
  off_time: string;
};

export type FeederScheduleSlot = {
  enabled: boolean;
  time: string;
};

export type FeederActuatorState = {
  feeding: boolean;
  feed_count: number;
  last_fed: string;
  open_angle: number;
  duration_ms: number;
  schedule: FeederScheduleSlot[];
};

export type PumpActuatorState = {
  active: boolean;
  dose_count: number;
  last_dispensed: string;
  volume_ml: number;
};

export type ActuatorState = LightActuatorState | FeederActuatorState | PumpActuatorState;

export type ActuatorStateSnapshot = {
  actuator: ActuatorName;
  state: ActuatorState | null;
  refreshed_at: string | null;
};

export type DeviceActuatorStatus = {
  tank_id: number;
  device_id: string;
  device_online: boolean;
  device_freshness: 'online' | 'offline' | 'unknown';
  last_seen_at: string | null;
  checked_at: string;
  actuators: ActuatorStateSnapshot[];
};

export type ActuatorCommand = {
  command_id: string;
  tank_id: number;
  device_id: string;
  actor_user_id: number | null;
  actor_name: string | null;
  actuator: ActuatorName;
  action: ActuatorAction;
  payload: Record<string, unknown>;
  status: ActuatorCommandStatus;
  requested_at: string;
  expires_at: string;
  executing_at: string | null;
  execution_at: string | null;
  result: Record<string, unknown> | null;
  error: string | null;
};

export type ActuatorCommandHistoryPage = {
  items: ActuatorCommand[];
  page: number;
  page_size: number;
  total: number;
  total_pages: number;
  has_previous: boolean;
  has_next: boolean;
  summary: ActuatorHistorySummary;
};

export type ActuatorHistorySummary = {
  total: number;
  queued: number;
  executing: number;
  succeeded: number;
  failed: number;
  expired: number;
};

export type Threshold = {
  parameter: string;
  unit: string;
  warning_min: number | null;
  warning_max: number | null;
  critical_min: number | null;
  critical_max: number | null;
  enabled: boolean;
};

export type SpeciesSuitabilityStatus = 'suitable' | 'attention' | 'unavailable';

export type SpeciesSuitabilityReason =
  | 'within_preferred_range'
  | 'below_preferred_minimum'
  | 'above_preferred_maximum'
  | 'species_range_missing'
  | 'no_current_reading'
  | 'stale_reading'
  | 'reading_value_missing'
  | 'invalid_species_range';

export type SpeciesSuitabilityCheck = {
  parameter: 'temperature' | 'ph' | 'dissolved_oxygen' | 'tds';
  status: SpeciesSuitabilityStatus;
  configured: boolean;
  reason: SpeciesSuitabilityReason;
  current_value: number | null;
  preferred_min: number | null;
  preferred_max: number | null;
  unit: string;
  message: string;
};

export type SpeciesSuitabilitySpecies = {
  fish_species_id: number;
  common_name: string;
  scientific_name: string;
  status: SpeciesSuitabilityStatus;
  checks: SpeciesSuitabilityCheck[];
};

export type SpeciesSuitabilityResponse = {
  tank_id: number;
  status: SpeciesSuitabilityStatus;
  summary_reason: 'no_species_assigned' | null;
  evaluated_at: string;
  reading: { id: number; timestamp: string; freshness: 'current' | 'stale'; } | null;
  species_counts: Record<SpeciesSuitabilityStatus, number>;
  species: SpeciesSuitabilitySpecies[];
};
