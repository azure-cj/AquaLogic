"""Local opt-in review launcher. Usage: python operator_review.py start|stop|reset|status."""
import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path
from urllib.request import urlopen

ROOT=Path(__file__).resolve().parents[1]
REVIEW=(ROOT/'.operator-review').resolve()
DATABASE=(REVIEW/'review.db').resolve()
STATE=REVIEW/'processes.json'
PYTHON=ROOT/'backend/.venv/Scripts/python.exe'
SERVER=ROOT/'scripts/operator_review_server.py'
VITE=ROOT/'web/node_modules/vite/bin/vite.js'
CONFIG=ROOT/'web/vite.review.config.ts'


def safe_paths():
    if REVIEW.parent != ROOT or DATABASE.parent != REVIEW or REVIEW.is_symlink() or REVIEW != ROOT/'.operator-review':
        raise RuntimeError('Review path containment check failed.')


def port(first,last):
    for candidate in range(first,last+1):
        with socket.socket() as connection:
            try: connection.bind(('127.0.0.1',candidate));return candidate
            except OSError: pass
    raise RuntimeError('No available isolated loopback port.')


def clean_environment(api_port,web_port):
    # Inherit only operating-system/runtime paths, never project/production secrets.
    env={key:value for key,value in os.environ.items() if key.upper() in {'SYSTEMROOT','WINDIR','PATH','PATHEXT','TEMP','TMP','USERPROFILE','APPDATA','LOCALAPPDATA','COMSPEC','PROGRAMFILES','PROGRAMFILES(X86)'}}
    env.update(AQUALOGIC_SYNTHETIC_REVIEW='1',AQUALOGIC_REVIEW_API_PORT=str(api_port),ENVIRONMENT='development',DEBUG='false',
        DATABASE_URL=f'sqlite:///{DATABASE.as_posix()}',MEDIA_ROOT=str(REVIEW/'media'),
        JWT_SECRET_KEY='synthetic-local-review-only-2026-not-a-production-secret',
        DEMO_SENSOR_ENABLED='false',DEMO_SENSOR_INSTANCE='false',PUSH_NOTIFICATIONS_ENABLED='false',MONITORING_INCIDENTS_ENABLED='false',
        TRUSTED_HOSTS='127.0.0.1,localhost',CORS_ORIGINS=f'http://127.0.0.1:{web_port}',PUBLIC_BASE_URL=f'http://127.0.0.1:{web_port}',PUBLIC_IMAGE_HOSTS='',
        VITE_SYNTHETIC_REVIEW='1',VITE_API_BASE_URL='/api')
    return env


def powershell(script):
    result=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',script],capture_output=True,text=True,check=True,
        creationflags=subprocess.CREATE_NO_WINDOW)
    return result.stdout.strip()


def identity(pid):
    output=powershell(f"$reviewProcess=Get-CimInstance Win32_Process -Filter 'ProcessId = {int(pid)}'; if ($reviewProcess) {{ [PSCustomObject]@{{ command=$reviewProcess.CommandLine; created=$reviewProcess.CreationDate.ToUniversalTime().ToString('o') }} | ConvertTo-Json -Compress }}")
    return json.loads(output) if output else None


def stop():
    if not STATE.exists(): return
    state=json.loads(STATE.read_text())
    for process in state['processes']:
        current=identity(process['pid'])
        if current is None: continue
        if current != process['identity'] or process['marker'].lower() not in current['command'].lower():
            raise RuntimeError('Refusing to stop a process whose verified review identity has changed.')
        powershell(f"Stop-Process -Id {int(process['pid'])} -ErrorAction Stop")
    STATE.unlink()
    print('Verified synthetic review processes stopped.')


def wait_url(url,process):
    deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        if process.poll() is not None: raise RuntimeError('Review process exited; inspect dedicated logs.')
        try:
            with urlopen(url,timeout=1) as response:
                if response.status==200:return
        except OSError: pass
        time.sleep(.25)
    raise RuntimeError('Review startup timed out; inspect dedicated logs.')


def start():
    if STATE.exists():
        state=json.loads(STATE.read_text())
        if any(identity(item['pid']) is not None for item in state['processes']):
            print(f"Review already started: {state['url']}. Use status or reset.");return
        STATE.unlink()
    api_port,web_port=port(8800,8899),port(5180,5199)
    env=clean_environment(api_port,web_port)
    if not DATABASE.exists():
        subprocess.run([str(PYTHON),str(ROOT/'scripts/seed_operator_review.py')],env=env,cwd=ROOT/'backend',check=True,creationflags=subprocess.CREATE_NO_WINDOW)
    node=shutil.which('node.exe')
    if not node or not VITE.exists(): raise RuntimeError('Existing Node/Vite dependencies are required.')
    processes=[]
    state=dict(url=f'http://127.0.0.1:{web_port}',api_url=f'http://127.0.0.1:{api_port}',processes=processes)
    try:
        for name,args,cwd,marker,url in [
            ('api',[str(PYTHON),str(SERVER)],ROOT/'backend',str(SERVER),state['api_url']+'/health'),
            ('web',[node,str(VITE),'--config',str(CONFIG),'--host','127.0.0.1','--port',str(web_port)],ROOT/'web',str(CONFIG),state['url'])]:
            with (REVIEW/f'{name}.log').open('w',encoding='utf-8') as log:
                process=subprocess.Popen(args,cwd=cwd,env=env,stdin=subprocess.DEVNULL,stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW)
            processes.append(dict(pid=process.pid,marker=marker,identity=identity(process.pid)))
            STATE.write_text(json.dumps(state,indent=2),encoding='utf-8')
            wait_url(url,process)
    except Exception:
        stop();raise
    manifest=json.loads((REVIEW/'scenarios.json').read_text(encoding='utf-8'))
    for scenario in manifest['scenarios']:
        scenario['alert_urls']=[f"{state['url']}/admin/alerts?alert_id={id}" for id in scenario['alert_ids']]
        scenario['analytics_url']=None if scenario['scenario']=='retired' else f"{state['url']}/admin/analytics?{scenario['analytics_query']}"
        scenario['analytics_api_url']=f"{state['api_url']}/analytics/fleet?{scenario['api_query']}"
    (REVIEW/'scenarios.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(f"Synthetic review ready: {state['url']}/admin/login\nAdmin: admin@synthetic.example.com\nStaff: staff@synthetic.example.com\nPassword: SyntheticReview2026!\nScenario manifest: {REVIEW/'scenarios.json'}")


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['start','stop','reset','status']);args=parser.parse_args()
    if os.name!='nt':raise RuntimeError('This launcher uses verified Windows process identities.')
    safe_paths();REVIEW.mkdir(exist_ok=True)
    if args.action=='stop':stop()
    elif args.action=='reset':
        stop()
        # Fixed filenames only, verified resolved paths; never recursive deletion.
        for suffix in ('','-wal','-shm','-journal'):
            target=Path(str(DATABASE)+suffix)
            if target.resolve().parent != REVIEW or target.is_symlink():raise RuntimeError('Refusing unsafe database reset path.')
            target.unlink(missing_ok=True)
        start()
    elif args.action=='start':start()
    elif STATE.exists():
        state=json.loads(STATE.read_text());print(json.dumps(dict(url=state['url'],processes=[dict(pid=item['pid'],verified=identity(item['pid'])==item['identity']) for item in state['processes']]),indent=2))
    else:print('Synthetic review is stopped.')
