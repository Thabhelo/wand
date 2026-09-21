"""Package a local test .app; optionally sign, create a DMG, and notarize for release."""
import argparse
import plistlib
import shutil
import subprocess
import tempfile
import os
from urllib.parse import urlsplit
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--binary',type=Path,required=True,help='SwiftPM-built MacBridge executable')
p.add_argument('--identity',default='-',help='Developer ID Application identity; defaults to ad-hoc local testing')
p.add_argument('--dmg',action='store_true')
p.add_argument('--output',type=Path,default=ROOT/'dist/Wand.app')
p.add_argument('--notary-profile',help='Existing notarytool Keychain profile; never pass passwords here')
p.add_argument('--relay-origin',default='',help='Production HTTPS relay baked into the signed app; no user configuration required')
p.add_argument('--dashboard-origin',default='',help='Optional separate HTTPS account dashboard origin')
a=p.parse_args()
for configured_origin in (a.relay_origin,a.dashboard_origin):
    if not configured_origin: continue
    u=urlsplit(configured_origin)
    if u.scheme!='https' or not u.hostname or u.username or u.password or u.query or u.fragment or u.path not in ('','/'):
        p.error('Configured origins must be plain HTTPS origins')
if not a.binary.is_file(): p.error('Build MacBridge before packaging')
if a.notary_profile and (a.identity=='-' or not a.dmg): p.error('Notarization requires a Developer ID identity and --dmg')
destination=a.output.resolve()
if destination.suffix!='.app': p.error('--output must be an .app path')
destination.parent.mkdir(parents=True,exist_ok=True)
staging=Path(tempfile.mkdtemp(prefix='.macbridge-build-',dir=destination.parent))
app=staging/destination.name
contents=app/'Contents'
for folder in ['MacOS','Resources']: (contents/folder).mkdir(parents=True,exist_ok=True)
shutil.copy2(a.binary,contents/'MacOS/MacBridge')
shutil.copy2(ROOT/'assets/Wand.icns',contents/'Resources/Wand.icns')
shutil.copy2(ROOT/'contracts/v1.schema.json',contents/'Resources/v1.schema.json')
shutil.copy2(ROOT/'contracts/actions.json',contents/'Resources/actions.json')
with (contents/'Info.plist').open('wb') as f:
    plistlib.dump(dict(CFBundleName='Wand',CFBundleDisplayName='Wand',CFBundleExecutable='MacBridge',
        CFBundleIconFile='Wand.icns',CFBundleIdentifier='local.macbridge.agent',CFBundlePackageType='APPL',CFBundleShortVersionString='0.9.3',
        CFBundleVersion='12',MacBridgeRelayOrigin=a.relay_origin,MacBridgeDashboardOrigin=a.dashboard_origin,LSMinimumSystemVersion='26.0',LSUIElement=True,NSHighResolutionCapable=True,NSAppleEventsUsageDescription="Wand controls approved media apps when you request playback actions."),f)
def run(args): subprocess.run(args,check=True)
# Remove disallowed Finder/resource-fork metadata only from this generated bundle.
for attr in ['com.apple.FinderInfo','com.apple.ResourceFork']:
    subprocess.run(['xattr','-dr',attr,str(app)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=False)
sign=['codesign','--force','--sign',a.identity]
if a.identity!='-':
    entitlements=contents/'Resources/Entitlements.plist'
    with entitlements.open('wb') as f: plistlib.dump({'com.apple.security.automation.apple-events':True},f)
    sign += ['--options','runtime','--timestamp','--entitlements',str(entitlements)]
run(sign+[str(app)])
run(['codesign','--verify','--strict',str(app)])
# Publish by renaming the completed bundle; never overwrite a running executable in place.
previous=staging/'previous.app'
if destination.exists(): os.replace(destination,previous)
try: os.replace(app,destination)
except BaseException:
    if previous.exists(): os.replace(previous,destination)
    raise
app=destination
shutil.rmtree(staging)
if a.dmg:
    dmg=ROOT/'dist/Wand.dmg'
    dmg.parent.mkdir(parents=True,exist_ok=True)
    run(['hdiutil','create','-volname','Wand','-srcfolder',str(app),'-ov','-format','UDZO',str(dmg)])
    if a.identity!='-': run(['codesign','--force','--sign',a.identity,'--timestamp',str(dmg)])
    if a.notary_profile:
        run(['xcrun','notarytool','submit',str(dmg),'--keychain-profile',a.notary_profile,'--wait'])
        run(['xcrun','stapler','staple',str(dmg)])
        run(['xcrun','stapler','validate',str(dmg)])
print(app)
print('Local test build only; no notarization performed.' if not a.notary_profile else 'Notarized DMG complete.')
