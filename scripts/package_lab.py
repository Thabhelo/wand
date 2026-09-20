"""Package a local test .app; optionally sign, create a DMG, and notarize for release."""
import argparse
import plistlib
import shutil
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--binary',type=Path,required=True,help='SwiftPM-built MacBridgeLab executable')
p.add_argument('--identity',default='-',help='Developer ID Application identity; defaults to ad-hoc local testing')
p.add_argument('--dmg',action='store_true')
p.add_argument('--output',type=Path,default=ROOT/'dist/MacBridge Lab.app')
p.add_argument('--notary-profile',help='Existing notarytool Keychain profile; never pass passwords here')
a=p.parse_args()
if not a.binary.is_file(): p.error('Build MacBridgeLab before packaging')
if a.notary_profile and (a.identity=='-' or not a.dmg): p.error('Notarization requires a Developer ID identity and --dmg')
app=a.output.resolve()
if app.suffix!='.app': p.error('--output must be an .app path')
contents=app/'Contents'
for folder in ['MacOS','Resources']: (contents/folder).mkdir(parents=True,exist_ok=True)
shutil.copy2(a.binary,contents/'MacOS/MacBridgeLab')
shutil.copy2(ROOT/'contracts/v1.schema.json',contents/'Resources/v1.schema.json')
shutil.copy2(ROOT/'contracts/actions.json',contents/'Resources/actions.json')
with (contents/'Info.plist').open('wb') as f:
    plistlib.dump(dict(CFBundleName='MacBridge Lab',CFBundleDisplayName='MacBridge Lab',CFBundleExecutable='MacBridgeLab',
        CFBundleIdentifier='local.macbridge.lab',CFBundlePackageType='APPL',CFBundleShortVersionString='0.2.0',
        CFBundleVersion='2',LSMinimumSystemVersion='26.0',LSUIElement=True,NSHighResolutionCapable=True),f)
def run(args): subprocess.run(args,check=True)
# Remove disallowed Finder/resource-fork metadata only from this generated bundle.
for attr in ['com.apple.FinderInfo','com.apple.ResourceFork']:
    subprocess.run(['xattr','-dr',attr,str(app)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=False)
sign=['codesign','--force','--sign',a.identity]
if a.identity!='-': sign += ['--options','runtime','--timestamp']
run(sign+[str(app)])
run(['codesign','--verify','--strict',str(app)])
if a.dmg:
    dmg=ROOT/'dist/MacBridge-Lab.dmg'
    run(['hdiutil','create','-volname','MacBridge Lab','-srcfolder',str(app),'-ov','-format','UDZO',str(dmg)])
    if a.identity!='-': run(['codesign','--force','--sign',a.identity,'--timestamp',str(dmg)])
    if a.notary_profile:
        run(['xcrun','notarytool','submit',str(dmg),'--keychain-profile',a.notary_profile,'--wait'])
        run(['xcrun','stapler','staple',str(dmg)])
        run(['xcrun','stapler','validate',str(dmg)])
print(app)
print('Local test build only; no notarization performed.' if not a.notary_profile else 'Notarized DMG complete.')
