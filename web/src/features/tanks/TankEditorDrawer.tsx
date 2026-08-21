import { api } from '@/shared/api/client';
import type { Tank } from '@/shared/api/models';
import { Drawer, Notice } from '@/shared/components/admin-ui';
import { ExternalLink, ImagePlus, Trash2, Upload } from 'lucide-react';
import { FormEvent, useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';

const MAX_HERO_IMAGE_BYTES = 5 * 1024 * 1024;
const HERO_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

function TankForm({ initial, onDone }: { initial?: Tank; onDone: () => void }) {
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [heroUrl, setHeroUrl] = useState(initial?.hero_image_url ?? '');
  const [heroFile, setHeroFile] = useState<File | null>(null);
  const [heroPreview, setHeroPreview] = useState(initial?.hero_image_url ?? '');
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!heroFile) {
      setHeroPreview(heroUrl);
      return;
    }
    const objectUrl = URL.createObjectURL(heroFile);
    setHeroPreview(objectUrl);
    return () => URL.revokeObjectURL(objectUrl);
  }, [heroFile, heroUrl]);

  const clearHero = () => {
    setHeroFile(null);
    setHeroUrl('');
    setHeroPreview('');
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const selectHeroFile = (file: File | undefined) => {
    if (!file) return;
    if (!HERO_IMAGE_TYPES.includes(file.type)) {
      setError('Choose a JPG, PNG, or WebP image.');
      return;
    }
    if (file.size > MAX_HERO_IMAGE_BYTES) {
      setError('Hero images must be 5 MB or smaller.');
      return;
    }
    setError('');
    setHeroUrl('');
    setHeroFile(file);
  };

  const useHeroUrl = (value: string) => {
    setHeroUrl(value);
    if (heroFile) {
      setHeroFile(null);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    const form = new FormData(event.currentTarget);
    const value = (name: string) => String(form.get(name) ?? '').trim();
    const volume = value('volume_liters');
    const savedHeroUrl = heroFile ? (initial?.hero_image_url ?? null) : (value('hero_image_url') || null);
    const body = {
      name: value('name'),
      location: value('location'),
      public_location: value('public_location') || null,
      description: value('description') || null,
      is_public: form.get('is_public') === 'on',
      feeding_schedule: value('feeding_schedule') || null,
      public_care_notes: value('public_care_notes') || null,
      tank_code: value('tank_code') || null,
      habitat_label: value('habitat_label') || null,
      water_type: value('water_type') || null,
      volume_liters: volume ? Number(volume) : null,
      established_on: value('established_on') || null,
      hero_image_url: savedHeroUrl,
    };

    try {
      const saved = await api<Tank>(initial ? `/tanks/${initial.id}` : '/tanks', {
        method: initial ? 'PUT' : 'POST',
        body: JSON.stringify(body),
      });
      if (heroFile && initial) {
        const upload = new FormData();
        upload.append('image', heroFile);
        try {
          await api(`/tanks/${saved.id}/hero-image`, { method: 'POST', body: upload });
        } catch (caught) {
          setError(caught instanceof Error
            ? `Tank saved, but the hero image could not be uploaded: ${caught.message}`
            : 'Tank saved, but the hero image could not be uploaded.');
          return;
        }
      }
      onDone();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Could not save tank');
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className="drawer-form" id="tank-form" onSubmit={submit}>
      {error && <Notice tone="error">{error}</Notice>}

      <div className="form-section">
        <div>
          <h3>Tank identity</h3>
          <p className="form-section-copy">The name and location staff use to identify this installation.</p>
        </div>
        <div className="form-grid">
          <label className="field">
            <span>Tank name</span>
            <input name="name" defaultValue={initial?.name} required maxLength={100} autoFocus={!initial} />
          </label>
          <label className="field">
            <span>Location</span>
            <input name="location" defaultValue={initial?.location} required maxLength={150} />
          </label>
        </div>
        <label className="field">
          <span>Description <small>Optional</small></span>
          <textarea name="description" defaultValue={initial?.description ?? ''} rows={3} maxLength={10_000} />
        </label>
      </div>

      <div className="form-section">
        <div>
          <h3>Public profile</h3>
          <p className="form-section-copy">Details visitors can see from the tank’s public QR page.</p>
        </div>
        <div className="form-grid">
          <label className="field">
            <span>Public location <small>Optional</small></span>
            <input name="public_location" defaultValue={initial?.public_location ?? ''} maxLength={150} placeholder="e.g. Main gallery" />
          </label>
          <label className="field">
            <span>Display code <small>Optional</small></span>
            <input name="tank_code" defaultValue={initial?.tank_code ?? ''} maxLength={32} placeholder="e.g. TANK-01" />
          </label>
          <label className="field">
            <span>Habitat label <small>Optional</small></span>
            <input name="habitat_label" defaultValue={initial?.habitat_label ?? ''} maxLength={80} placeholder="e.g. Tropical community" />
          </label>
          <label className="field">
            <span>Water type</span>
            <select name="water_type" defaultValue={initial?.water_type ?? ''}>
              <option value="">Not specified</option>
              <option value="freshwater">Freshwater</option>
              <option value="saltwater">Saltwater</option>
              <option value="brackish">Brackish</option>
            </select>
          </label>
          <label className="field">
            <span>Volume <small>Liters</small></span>
            <input name="volume_liters" type="number" min="1" step="1" defaultValue={initial?.volume_liters ?? ''} placeholder="e.g. 180" />
          </label>
          <label className="field">
            <span>Established on <small>Optional</small></span>
            <input name="established_on" type="date" defaultValue={initial?.established_on ?? ''} />
          </label>
        </div>
      </div>

      <div className="form-section">
        <div>
          <h3>Hero image</h3>
          <p className="form-section-copy">Add a wide image for the public tank page. Use a hosted HTTPS image or upload a local image.</p>
        </div>
        <label className="field">
          <span>Image URL <small>HTTPS only</small></span>
          <input
            name="hero_image_url"
            type="url"
            value={heroUrl}
            onChange={(event) => useHeroUrl(event.target.value)}
            placeholder="https://images.example.com/tank.jpg"
            maxLength={500}
            disabled={Boolean(heroFile)}
            aria-describedby="hero-image-help"
          />
        </label>
        <label className="field">
          <span>Upload image <small>JPG, PNG, or WebP · max 5 MB</small></span>
          <span className="file-input-wrap">
            <Upload size={16} aria-hidden="true" />
            <input
              ref={fileInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp"
              onChange={(event) => selectHeroFile(event.target.files?.[0])}
              disabled={!initial || busy}
            />
          </span>
          <small id="hero-image-help" className="field-help">
            {initial ? 'Uploading replaces the current hero image after you save.' : 'Save the tank first, then edit it to upload an image.'}
          </small>
        </label>
        {heroPreview ? (
          <div className="hero-image-preview-wrap">
            <img className="hero-image-preview" src={heroPreview} alt="Hero image preview" onError={() => setHeroPreview('')} />
            <button className="button button-secondary hero-image-clear" type="button" onClick={clearHero} disabled={busy}>
              <Trash2 size={15} /> Remove image
            </button>
          </div>
        ) : (
          <div className="hero-image-empty" role="status">
            <ImagePlus size={20} aria-hidden="true" />
            <span>No hero image selected</span>
          </div>
        )}
      </div>

      <div className="form-section">
        <div>
          <h3>Public content</h3>
          <p className="form-section-copy">Helpful context for visitors viewing the QR page.</p>
        </div>
        <label className="field">
          <span>Feeding schedule <small>Optional</small></span>
          <textarea name="feeding_schedule" defaultValue={initial?.feeding_schedule ?? ''} rows={3} maxLength={10_000} placeholder="e.g. Daily at 08:00 and 18:00" />
        </label>
        <label className="field">
          <span>Care notes <small>Optional</small></span>
          <textarea name="public_care_notes" defaultValue={initial?.public_care_notes ?? ''} rows={4} maxLength={10_000} placeholder="Share a short care note with visitors." />
        </label>
      </div>

      <div className="form-section form-section-visibility">
        <div>
          <h3>Visibility</h3>
          <p className="form-section-copy">Control whether this tank can be opened from its public QR link.</p>
        </div>
        <label className="toggle-field">
          <input type="checkbox" name="is_public" defaultChecked={initial?.is_public ?? true} />
          <span aria-hidden="true" />
          <strong>Show public tank page</strong>
        </label>
      </div>

      <button className="sr-only" disabled={busy}>Save tank</button>
      {busy && <p className="form-progress">Saving tank…</p>}
    </form>
  );
}

export function TankEditorDrawer({
  open,
  tank,
  onClose,
  onSaved,
}: {
  open: boolean;
  tank?: Tank;
  onClose: () => void;
  onSaved: () => void;
}) {
  return (
    <Drawer
      open={open}
      title={tank ? `Edit ${tank.name}` : 'Add tank'}
      description={tank ? 'Update tank details and public page content.' : 'Register a new tank and its public page details.'}
      onClose={onClose}
      footer={(
        <div className="drawer-actions">
          <button className="button button-secondary" type="button" onClick={onClose}>
            Cancel
          </button>
          <button className="button button-primary" type="submit" form="tank-form">
            Save tank
          </button>
        </div>
      )}
    >
      {tank && (
        <Link className="text-link drawer-detail-link" to={`/admin/tanks/${tank.id}`} onClick={onClose}>
          View full tank details <ExternalLink size={14} />
        </Link>
      )}
      <TankForm initial={tank} onDone={onSaved} />
    </Drawer>
  );
}
