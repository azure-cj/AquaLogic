"""Explicit opt-in entry point for the isolated synthetic API."""
import os
import json
from html import escape
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATABASE = (ROOT / '.operator-review' / 'review.db').resolve()
if DATABASE.parent.parent != ROOT or (ROOT / '.operator-review').is_symlink() or os.environ.get('AQUALOGIC_SYNTHETIC_REVIEW') != '1' or os.environ.get('DATABASE_URL') != f'sqlite:///{DATABASE.as_posix()}':
    raise RuntimeError('This entry point accepts only the dedicated synthetic review database.')
sys.path.insert(0, str(ROOT / 'backend'))

from app.main import app  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from fastapi.responses import HTMLResponse  # noqa: E402
import uvicorn  # noqa: E402


@app.middleware('http')
async def synthetic_boundary(request, call_next):
    if request.method not in ('GET', 'HEAD', 'OPTIONS') and any(word in request.url.path for word in ('/devices', '/actuators', '/push', '/bridge')):
        return JSONResponse({'detail': 'Hardware and push writes are disabled in synthetic review.'}, status_code=403)
    response = await call_next(request)
    response.headers['X-AquaLogic-Data'] = 'synthetic-review'
    return response


@app.get('/synthetic-review', response_class=HTMLResponse, include_in_schema=False)
def scenario_index():
    manifest = json.loads((ROOT / '.operator-review/scenarios.json').read_text(encoding='utf-8'))
    sections = []
    for item in manifest['scenarios']:
        links = ' · '.join(f'<a href="{escape(url)}">Alert #{id}</a>' for id, url in zip(item['alert_ids'], item['alert_urls']))
        if item['analytics_url']:
            links += f' · <a href="{escape(item["analytics_url"])}">Exact Analytics window</a>'
        findings = [(card['title'], card['evidence']) for card in item['expected_cards'] if card['parameter'] == item['parameter']]
        sections.append(f'<section><h2>{escape(item["tank_name"])}</h2><p>{links}</p><pre>{escape(json.dumps(findings, indent=2))}</pre><details><summary>Species context at reset and all evidence</summary><pre>{escape(json.dumps(item, indent=2))}</pre></details></section>')
    return f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>AquaLogic synthetic review scenarios</title>
<style>body{{font:16px system-ui;max-width:1000px;margin:32px auto;padding:0 16px;background:#f5faf9;color:#123a37}}section{{background:white;border:1px solid #bad1cb;padding:20px;margin:16px 0;border-radius:12px}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}}a{{color:#006a60}}.label{{padding:16px;background:#fff1c2}}</style>
<h1>Synthetic review data</h1><p class="label">Dedicated local API and SQLite. No live aquarium connection. Fictional species preferences; engineering heuristics are not safety limits.</p>
<p>Sign in through an alert or Analytics link using <strong>admin@synthetic.example.com</strong> or <strong>staff@synthetic.example.com</strong>, password <strong>SyntheticReview2026!</strong>.</p>
<p>Reset: {escape(manifest['reset_at'])}. Historical window: {escape(manifest['window_start'])} through {escape(manifest['window_end'])} (UTC; graphs display Manila time).</p>
<p>Fresh species comparisons expire after 90 seconds. Run the reset command and sign in again to inspect fresh counts. Historical findings remain reproducible. The retired scenario has an alert link and authenticated API evidence; the existing web Analytics chooser lists active tanks.</p>
{''.join(sections)}</html>'''


if __name__ == '__main__':
    uvicorn.run(app, host='127.0.0.1', port=int(os.environ['AQUALOGIC_REVIEW_API_PORT']))
