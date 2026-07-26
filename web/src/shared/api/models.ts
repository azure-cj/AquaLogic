import type { FleetStatus } from '@/shared/components/admin-ui';
import type { Reading } from './client';

export type Tank = {
  id: number;
  public_id: string;
  name: string;
  location: string;
  description?: string | null;
  is_public: boolean;
  customer_id?: number | null;
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
  photo_url?: string | null;
  description?: string | null;
  diet?: string | null;
  compatibility_notes?: string | null;
  care_tips?: string | null;
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
