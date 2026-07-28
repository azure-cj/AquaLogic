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
