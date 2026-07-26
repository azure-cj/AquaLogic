import { api } from '@/shared/api/client';
import { useQuery } from '@tanstack/react-query';
import {
  Activity,
  Camera,
  ChevronDown,
  CircleHelp,
  Clock3,
  Droplets,
  FishSymbol,
  FlaskConical,
  Gauge,
  Info,
  Mail,
  MapPin,
  MessageCircle,
  Phone,
  Share2,
  ShieldCheck,
  Thermometer,
  Utensils,
  Waves,
  Wind,
} from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { useParams } from 'react-router-dom';
import { businessProfile, publicFaqs, VisitorRule, visitorRules } from './content';
import './styles.css';

type PublicStatus = 'normal' | 'warning' | 'critical' | 'offline';
type MetricStatus = PublicStatus | 'unavailable';
type WaterType = 'freshwater' | 'saltwater' | 'brackish';

type PublicReading = {
  timestamp: string;
  temperature: number;
  ph: number;
  turbidity: number;
  dissolved_oxygen: number;
  tds: number;
  ammonia: number;
};

type PublicFish = {
  id: number;
  common_name: string;
  scientific_name: string;
  photo_url?: string | null;
  description?: string | null;
  ideal_temp_min?: number | null;
  ideal_temp_max?: number | null;
  ideal_ph_min?: number | null;
  ideal_ph_max?: number | null;
  diet?: string | null;
  compatibility_notes?: string | null;
  care_tips?: string | null;
};

type PublicTankResponse = {
  public_id: string;
  name: string;
  location: string;
  description?: string | null;
  tank_code?: string | null;
  habitat_label?: string | null;
  water_type?: WaterType | null;
  volume_liters?: number | null;
  established_on?: string | null;
  hero_image_url?: string | null;
  fish_species: PublicFish[];
  latest_reading?: PublicReading | null;
  status: PublicStatus;
  parameter_statuses?: Record<string, MetricStatus>;
  feeding_schedule?: string | null;
  public_care_notes?: string | null;
};

type MetricDefinition = {
  key: keyof Omit<PublicReading, 'timestamp'>;
  label: string;
  unit: string;
  digits: number;
  icon: typeof Thermometer;
};

const primaryMetrics: MetricDefinition[] = [
  { key: 'temperature', label: 'Water temperature', unit: '°C', digits: 1, icon: Thermometer },
  { key: 'ph', label: 'pH balance', unit: 'pH', digits: 1, icon: FlaskConical },
  { key: 'dissolved_oxygen', label: 'Oxygen level', unit: 'mg/L', digits: 1, icon: Wind },
  { key: 'turbidity', label: 'Water clarity', unit: 'NTU', digits: 1, icon: Waves },
];

const secondaryMetrics: MetricDefinition[] = [
  { key: 'tds', label: 'Dissolved solids', unit: 'ppm', digits: 0, icon: Gauge },
  { key: 'ammonia', label: 'Ammonia', unit: 'ppm', digits: 2, icon: Activity },
];

const overallCopy: Record<
  PublicStatus,
  { label: string; message: string; }
> = {
  normal: {
    label: 'Water conditions healthy',
    message: 'Current readings are within the configured care ranges.',
  },
  warning: {
    label: 'Under monitoring',
    message: 'A reading needs attention and the team has been notified.',
  },
  critical: {
    label: 'Staff alerted',
    message: 'The care team has received an alert and is responding.',
  },
  offline: {
    label: 'Sensor offline',
    message: 'Live readings are temporarily unavailable. The tank remains under staff care.',
  },
};

const metricCopy: Record<MetricStatus, string> = {
  normal: 'Healthy',
  warning: 'Monitoring',
  critical: 'Needs attention',
  offline: 'Last known',
  unavailable: 'Unavailable',
};

const ruleIcons = {
  glass: ShieldCheck,
  flash: Camera,
  feeding: Utensils,
  questions: MessageCircle,
} satisfies Record<VisitorRule['id'], typeof ShieldCheck>;

const titleCase = (value: string) => value.charAt(0).toUpperCase() + value.slice(1);

const formatEstablished = (value: string) =>
  new Intl.DateTimeFormat('en-PH', { month: 'short', year: 'numeric' }).format(
    new Date(`${value}T00:00:00`),
  );

const timeAgo = (value?: string | null) => {
  if (!value) return 'No readings yet';
  const seconds = Math.max(0, Math.round((Date.now() - new Date(value).getTime()) / 1000));
  if (seconds < 60) return 'Updated just now';
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `Updated ${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `Updated ${hours} hr ago`;
  return `Updated ${Math.round(hours / 24)} days ago`;
};

function FishPhoto({ fish }: { fish: PublicFish; }) {
  const [failed, setFailed] = useState(false);
  if (!fish.photo_url || failed) {
    return (
      <div className="visitor-fish-fallback" aria-hidden="true">
        <FishSymbol size={38} />
      </div>
    );
  }
  return (
    <img
      src={fish.photo_url}
      alt={`${fish.common_name} in an aquarium`}
      loading="lazy"
      onError={() => setFailed(true)}
    />
  );
}

function MetricCard({
  metric,
  reading,
  status,
}: {
  metric: MetricDefinition;
  reading?: PublicReading | null;
  status: MetricStatus;
}) {
  const Icon = metric.icon;
  const value = reading?.[metric.key];
  return (
    <article className="visitor-metric" data-status={status}>
      <div className="visitor-metric-topline">
        <span className="visitor-icon-bubble">
          <Icon size={18} aria-hidden="true" />
        </span>
        <span className="visitor-metric-status">
          <i aria-hidden="true" />
          {metricCopy[status]}
        </span>
      </div>
      <p>{metric.label}</p>
      <strong>
        {value == null ? '—' : value.toFixed(metric.digits)}
        <small>{value == null ? '' : metric.unit}</small>
      </strong>
      <span className="visitor-status-rail" aria-hidden="true" />
    </article>
  );
}

export function PublicTank() {
  const { publicId = '' } = useParams();
  const [shareNote, setShareNote] = useState('');
  const [heroFailed, setHeroFailed] = useState(false);
  const query = useQuery({
    queryKey: ['public-tank', publicId],
    queryFn: () => api<PublicTankResponse>(`/public/tanks/${publicId}`),
    retry: false,
    refetchInterval: 30_000,
  });

  const tank = query.data;
  const heroImage = useMemo(
    () =>
      tank?.hero_image_url ||
      tank?.fish_species.find((fish) => Boolean(fish.photo_url))?.photo_url ||
      null,
    [tank],
  );

  useEffect(() => {
    setHeroFailed(false);
  }, [heroImage]);

  useEffect(() => {
    if (!tank) return;
    const previous = document.title;
    document.title = `${tank.name} · JRed Aquatics`;
    return () => {
      document.title = previous;
    };
  }, [tank]);

  if (query.isLoading) {
    return (
      <main className="visitor-state-page" aria-live="polite">
        <span className="visitor-loader" aria-hidden="true" />
        <h1>Getting this tank ready</h1>
        <p>Loading its inhabitants and latest water conditions…</p>
      </main>
    );
  }

  if (query.isError || !tank) {
    return (
      <main className="visitor-state-page">
        <span className="visitor-state-icon">
          <Info size={28} />
        </span>
        <h1>Tank page unavailable</h1>
        <p>This QR page cannot be opened right now. A JRed Aquatics team member can help.</p>
      </main>
    );
  }

  const overall = overallCopy[tank.status];
  const parameterStatuses = tank.parameter_statuses ?? {};
  const advancedNeedsAttention = secondaryMetrics.filter((metric) =>
    ['warning', 'critical'].includes(parameterStatuses[metric.key]),
  );
  const advancedRemaining = secondaryMetrics.filter(
    (metric) => !advancedNeedsAttention.includes(metric),
  );
  const visibleMetrics = [...primaryMetrics, ...advancedNeedsAttention];
  const waterType = tank.water_type ? titleCase(tank.water_type) : null;
  const metadata = [
    waterType,
    tank.volume_liters ? `${tank.volume_liters} L` : null,
    tank.established_on ? `Est. ${formatEstablished(tank.established_on)}` : null,
  ].filter(Boolean);

  const share = async () => {
    const shareData = {
      title: `${tank.name} · JRed Aquatics`,
      text: `Meet the fish and see the live water conditions for ${tank.name}.`,
      url: window.location.href,
    };
    try {
      if (navigator.share) {
        await navigator.share(shareData);
        setShareNote('Shared');
      } else if (navigator.clipboard) {
        await navigator.clipboard.writeText(window.location.href);
        setShareNote('Link copied');
      } else {
        setShareNote('Use your browser menu to share this page');
      }
    } catch (error) {
      if ((error as DOMException).name !== 'AbortError') {
        setShareNote('Sharing is unavailable');
      }
    }
    window.setTimeout(() => setShareNote(''), 2500);
  };

  return (
    <div className="visitor-shell">
      <main className="visitor-page">
        <section className="visitor-hero" id="tank" aria-labelledby="tank-name">
          {heroImage && !heroFailed && (
            <img
              className="visitor-hero-image"
              src={heroImage}
              alt=""
              fetchPriority="high"
              onError={() => setHeroFailed(true)}
            />
          )}
          <div className="visitor-hero-shade" />
          <button className="visitor-share" type="button" onClick={share}>
            <Share2 size={18} aria-hidden="true" />
            <span className="sr-only">Share this tank</span>
          </button>
          <div className="visitor-hero-copy">
            <span className="visitor-kicker">
              <Waves size={14} aria-hidden="true" />
              {tank.habitat_label || waterType || 'Aquarium display'}
            </span>
            <h1 id="tank-name">{tank.name}</h1>
            {metadata.length > 0 && <p>{metadata.join(' · ')}</p>}
          </div>
        </section>

        <section className="visitor-summary" aria-label="Tank summary">
          <div className="visitor-summary-top">
            <span>
              <small>{tank.tank_code ? 'Tank ID' : 'Location'}</small>
              <strong>{tank.tank_code || tank.location}</strong>
            </span>
            <span className="visitor-overall-status" data-status={tank.status}>
              <small>Water status</small>
              <strong>{overall.label}</strong>
            </span>
          </div>
          <p>{tank.description || 'A carefully maintained aquarium cared for by JRed Aquatics.'}</p>
          <span className="visitor-update">
            <Clock3 size={14} aria-hidden="true" />
            {timeAgo(tank.latest_reading?.timestamp)}
          </span>
        </section>

        {shareNote && (
          <p className="visitor-toast" role="status">
            {shareNote}
          </p>
        )}

        <section className="visitor-section" aria-labelledby="conditions-title">
          <header className="visitor-section-heading">
            <div>
              <p className="visitor-eyebrow">Live from AquaLogic</p>
              <h2 id="conditions-title">Live water conditions</h2>
              <span>{overall.message}</span>
            </div>
            <Droplets size={24} aria-hidden="true" />
          </header>

          {!tank.latest_reading ? (
            <div className="visitor-empty">
              <Info size={20} aria-hidden="true" />
              <div>
                <strong>Waiting for the first reading</strong>
                <p>Tank information is still available while the sensor connects.</p>
              </div>
            </div>
          ) : (
            <>
              <div className="visitor-metric-grid">
                {visibleMetrics.map((metric) => (
                  <MetricCard
                    key={metric.key}
                    metric={metric}
                    reading={tank.latest_reading}
                    status={parameterStatuses[metric.key] || 'unavailable'}
                  />
                ))}
              </div>
              {advancedRemaining.length > 0 && (
                <details className="visitor-more-readings">
                  <summary>
                    <span>More water details</span>
                    <ChevronDown size={18} aria-hidden="true" />
                  </summary>
                  <div className="visitor-metric-grid">
                    {advancedRemaining.map((metric) => (
                      <MetricCard
                        key={metric.key}
                        metric={metric}
                        reading={tank.latest_reading}
                        status={parameterStatuses[metric.key] || 'unavailable'}
                      />
                    ))}
                  </div>
                </details>
              )}
            </>
          )}

          <div className="visitor-alert-note">
            <ShieldCheck size={18} aria-hidden="true" />
            <p>
              AquaLogic alerts the care team when a monitored reading leaves its configured range.
            </p>
          </div>
        </section>

        <section className="visitor-section" id="fish" aria-labelledby="fish-title">
          <header className="visitor-section-heading">
            <div>
              <p className="visitor-eyebrow">Meet the inhabitants</p>
              <h2 id="fish-title">Fish in this tank</h2>
              <span>
                {tank.fish_species.length
                  ? `${tank.fish_species.length} ${tank.fish_species.length === 1 ? 'species shares' : 'species share'} this habitat`
                  : 'Species information will be added soon'}
              </span>
            </div>
            <FishSymbol size={24} aria-hidden="true" />
          </header>

          {tank.fish_species.length ? (
            <div className="visitor-fish-list">
              {tank.fish_species.map((fish) => (
                <details className="visitor-fish-card" key={fish.id}>
                  <summary>
                    <FishPhoto fish={fish} />
                    <span className="visitor-fish-name">
                      <strong>{fish.common_name}</strong>
                      <i>{fish.scientific_name}</i>
                      <span className="visitor-fish-ranges">
                        {fish.ideal_temp_min != null && fish.ideal_temp_max != null && (
                          <b>
                            <Thermometer size={12} /> {fish.ideal_temp_min}–{fish.ideal_temp_max}°C
                          </b>
                        )}
                        {fish.ideal_ph_min != null && fish.ideal_ph_max != null && (
                          <b>
                            <FlaskConical size={12} /> pH {fish.ideal_ph_min}–{fish.ideal_ph_max}
                          </b>
                        )}
                      </span>
                    </span>
                    {waterType && <em>{waterType}</em>}
                    <ChevronDown className="visitor-fish-chevron" size={18} aria-hidden="true" />
                  </summary>
                  <div className="visitor-fish-detail">
                    {fish.description && <p>{fish.description}</p>}
                    {fish.diet && (
                      <p>
                        <strong>Diet</strong>
                        {fish.diet}
                      </p>
                    )}
                    {fish.care_tips && (
                      <p>
                        <strong>Care</strong>
                        {fish.care_tips}
                      </p>
                    )}
                    {fish.compatibility_notes && (
                      <p>
                        <strong>Compatibility</strong>
                        {fish.compatibility_notes}
                      </p>
                    )}
                  </div>
                </details>
              ))}
            </div>
          ) : (
            <div className="visitor-empty">
              <FishSymbol size={20} aria-hidden="true" />
              <div>
                <strong>The inhabitants are being catalogued</strong>
                <p>Ask the JRed team if you would like to identify a fish.</p>
              </div>
            </div>
          )}
        </section>

        {(tank.feeding_schedule || tank.public_care_notes) && (
          <section className="visitor-section" aria-labelledby="care-title">
            <header className="visitor-section-heading compact">
              <div>
                <p className="visitor-eyebrow">From the care team</p>
                <h2 id="care-title">Good to know</h2>
              </div>
              <Info size={24} aria-hidden="true" />
            </header>
            <div className="visitor-care-card">
              {tank.feeding_schedule && (
                <p>
                  <strong>Feeding schedule</strong>
                  {tank.feeding_schedule}
                </p>
              )}
              {tank.public_care_notes && (
                <p>
                  <strong>Care note</strong>
                  {tank.public_care_notes}
                </p>
              )}
            </div>
          </section>
        )}

        <section className="visitor-section" aria-labelledby="visitor-rules-title">
          <header className="visitor-section-heading">
            <div>
              <p className="visitor-eyebrow">A calm visit for everyone</p>
              <h2 id="visitor-rules-title">What visitors should know</h2>
            </div>
            <ShieldCheck size={24} aria-hidden="true" />
          </header>
          <div className="visitor-rule-list">
            {visitorRules.map((rule) => {
              const Icon = ruleIcons[rule.id];
              return (
                <article key={rule.id}>
                  <span className="visitor-icon-bubble">
                    <Icon size={18} aria-hidden="true" />
                  </span>
                  <div>
                    <h3>{rule.title}</h3>
                    <p>{rule.body}</p>
                  </div>
                </article>
              );
            })}
          </div>
        </section>

        <section className="visitor-section" aria-labelledby="faq-title">
          <header className="visitor-section-heading">
            <div>
              <p className="visitor-eyebrow">Questions visitors often ask</p>
              <h2 id="faq-title">Quick answers</h2>
            </div>
            <CircleHelp size={24} aria-hidden="true" />
          </header>
          <div className="visitor-faq-list">
            {publicFaqs.map((faq) => (
              <details key={faq.question}>
                <summary>
                  <CircleHelp size={16} aria-hidden="true" />
                  <span>{faq.question}</span>
                  <ChevronDown size={18} aria-hidden="true" />
                </summary>
                <p>{faq.answer}</p>
              </details>
            ))}
          </div>
        </section>

        <section className="visitor-section" id="visit" aria-labelledby="visit-title">
          <header className="visitor-section-heading">
            <div>
              <p className="visitor-eyebrow">Your local aquatics team</p>
              <h2 id="visit-title">About JRed Aquatics</h2>
              <span>{businessProfile.tagline}</span>
            </div>
            <Droplets size={24} aria-hidden="true" />
          </header>
          <article className="visitor-business-card">
            <div className="visitor-business-brand">
              <span>
                <Waves size={24} aria-hidden="true" />
              </span>
              <div>
                <strong>{businessProfile.name}</strong>
                <small>Powered by careful aquatics</small>
              </div>
            </div>
            <a
              href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
                businessProfile.address,
              )}`}
              target="_blank"
              rel="noreferrer"
            >
              <MapPin size={17} aria-hidden="true" />
              {businessProfile.address}
            </a>
            {businessProfile.phone && (
              <a href={`tel:${businessProfile.phone}`}>
                <Phone size={17} aria-hidden="true" />
                {businessProfile.phone}
              </a>
            )}
            {businessProfile.email && (
              <a href={`mailto:${businessProfile.email}`}>
                <Mail size={17} aria-hidden="true" />
                {businessProfile.email}
              </a>
            )}
            {businessProfile.openingHours && (
              <div className="visitor-hours">
                <span>
                  <Clock3 size={16} aria-hidden="true" /> Opening hours
                </span>
                {businessProfile.openingHours.map((row) => (
                  <p key={row.days}>
                    <span>{row.days}</span>
                    <strong>{row.hours}</strong>
                  </p>
                ))}
              </div>
            )}
          </article>
        </section>

        <footer className="visitor-footer">
          <strong>
            Aqua<span>Logic</span>
          </strong>
          <p>Live water insight · Thoughtful fish care</p>
          <small>© 2026 JRed Aquatics</small>
        </footer>
      </main>

      <nav className="visitor-nav" aria-label="On this page">
        <a href="#tank">
          <Droplets size={19} aria-hidden="true" />
          <span>Tank</span>
        </a>
        <a href="#fish">
          <FishSymbol size={19} aria-hidden="true" />
          <span>Fish</span>
        </a>
        <a href="#visit">
          <MapPin size={19} aria-hidden="true" />
          <span>Visit</span>
        </a>
      </nav>
    </div>
  );
}
