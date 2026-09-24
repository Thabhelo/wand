"""Release orchestration. Secrets only enter through CI environment, never repository files."""
import base64
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
LEGACY_TEAM = 'AX35NK3J3A'  # Preserve build 32's identity until an explicit migration.
SIGNING_SECRETS = ('WAND_CERTIFICATE_BASE64', 'WAND_CERTIFICATE_PASSWORD', 'WAND_NOTARY_KEY_BASE64',
                   'WAND_NOTARY_KEY_ID', 'WAND_NOTARY_ISSUER_ID')
PUBLICATION_SECRETS = ('GH_RELEASE_TOKEN', 'CLOUDFLARE_API_TOKEN')

def signing_team_id():
    team = os.environ.get('WAND_SIGNING_TEAM_ID') or LEGACY_TEAM
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise SystemExit('WAND_SIGNING_TEAM_ID must be Apple\'s 10-character uppercase Team ID.')
    return team

def signing_identity(identities, team):
    matches = re.findall(r'([A-F0-9]{40}) "Developer ID Application: [^"\n]+ \('+re.escape(team)+r'\)"', identities)
    if len(matches) != 1:
        raise SystemExit(f'Expected exactly one Developer ID Application signing identity for team {team}.')
    return matches[0]

def run(*args, capture=False, **kw):
    return subprocess.run(args, check=True, text=True, capture_output=capture, **kw)

def release():
    version, build = os.environ['RELEASE_VERSION'], os.environ['RELEASE_BUILD']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[1-9]\d*', build):
        raise SystemExit('Use a numeric x.y.z version and positive build number.')
    return version, int(build), f'Wand-{version}-build{build}'

def validate():
    signing_team_id()
    version, build, _ = release()
    page = (ROOT/'site/public/download/index.html').read_text()
    old = re.search(r'Build (\d+)', page)
    if not old or build <= int(old[1]):
        raise SystemExit('Build number must exceed the published build.')
    old_version = re.search(r'Wand-(\d+\.\d+\.\d+)-build', page)
    if old_version and tuple(map(int, version.split('.'))) < tuple(map(int, old_version[1].split('.'))):
        raise SystemExit('Version cannot decrease.')

def preflight(publish=False):
    validate()
    required = SIGNING_SECRETS + (PUBLICATION_SECRETS if publish else ())
    missing = [key for key in required if not os.environ.get(key)]
    if missing: raise SystemExit('Missing release secrets: ' + ', '.join(missing))

def package():
    preflight()
    team = signing_team_id()
    temp = Path(os.environ['RUNNER_TEMP'])
    cert, key, keychain = temp/'wand-signing.p12', temp/'wand-notary.p8', temp/'wand-release.keychain-db'
    for path, variable in [(cert, 'WAND_CERTIFICATE_BASE64'), (key, 'WAND_NOTARY_KEY_BASE64')]:
        path.write_bytes(base64.b64decode(os.environ[variable], validate=True)); path.chmod(0o600)
    password = os.urandom(32).hex()
    # Do not echo commands: security accepts these secrets as process arguments.
    run('security', 'create-keychain', '-p', password, str(keychain))
    run('security', 'set-keychain-settings', '-lut', '7200', str(keychain))
    run('security', 'unlock-keychain', '-p', password, str(keychain))
    run('security', 'import', str(cert), '-P', os.environ['WAND_CERTIFICATE_PASSWORD'], '-k', str(keychain), '-T', '/usr/bin/codesign')
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-k', password, str(keychain))
    run('security', 'list-keychains', '-d', 'user', '-s', str(keychain))
    ids = run('security', 'find-identity', '-v', '-p', 'codesigning', str(keychain), capture=True).stdout
    identity = signing_identity(ids, team)
    binpath = run('swift', 'build', '--package-path', 'agent', '-c', 'release', '--show-bin-path', capture=True).stdout.strip()
    version, build, name = release()
    run('python3', 'scripts/package_agent.py', '--binary', str(Path(binpath)/'MacBridge'), '--identity', identity,
        '--version', version, '--build-number', str(build), '--output', 'dist/Wand.app',
        '--relay-origin', 'https://api.getwand.app', '--dashboard-origin', 'https://app.getwand.app')
    auth = ['--key', str(key), '--key-id', os.environ['WAND_NOTARY_KEY_ID'], '--issuer', os.environ['WAND_NOTARY_ISSUER_ID']]
    def notarize(path):
        result = run('xcrun', 'notarytool', 'submit', str(path), *auth, '--wait', '--timeout', '30m', '--output-format', 'json', capture=True)
        status = json.loads(result.stdout)
        if status.get('status') != 'Accepted': raise SystemExit('Apple rejected notarization: '+str(status.get('id')))
    app = ROOT/'dist/Wand.app'
    archive = ROOT/'dist/Wand.zip'
    run('ditto', '-c', '-k', '--keepParent', str(app), str(archive)); notarize(archive)
    run('xcrun', 'stapler', 'staple', str(app)); run('xcrun', 'stapler', 'validate', str(app))
    run('codesign', '--verify', '--deep', '--strict', str(app))
    run('spctl', '--assess', '--type', 'execute', str(app))
    out = ROOT/'dist/release'; out.mkdir()
    dmg = out/(name+'.dmg')
    with tempfile.TemporaryDirectory(dir=temp) as folder:
        run('ditto', str(app), folder+'/Wand.app'); os.symlink('/Applications', folder+'/Applications')
        run('hdiutil', 'create', '-volname', 'Wand', '-srcfolder', folder, '-format', 'UDZO', str(dmg))
    run('codesign', '--sign', identity, '--timestamp', str(dmg)); notarize(dmg)
    run('xcrun', 'stapler', 'staple', str(dmg)); run('xcrun', 'stapler', 'validate', str(dmg))
    run('hdiutil', 'verify', str(dmg))
    (out/(name+'.sha256')).write_text(hashlib.sha256(dmg.read_bytes()).hexdigest()+'  '+dmg.name+'\n')
    for p in out.iterdir(): shutil.copy2(p, ROOT/'site/public/releases'/p.name)
    page = ROOT/'site/public/download/index.html'
    text = re.sub(r'Wand-\d+\.\d+\.\d+-build\d+', name, page.read_text())
    text = re.sub(r'Free beta · [\d.]+ · Build \d+', f'Free beta · {version} · Build {build}', text)
    page.write_text(text)

def publish():
    _, _, name = release()
    run('gh', 'auth', 'setup-git')
    run('git', 'fetch', 'origin', 'main')
    if run('git', 'rev-parse', 'HEAD', capture=True).stdout != run('git', 'rev-parse', 'origin/main', capture=True).stdout:
        raise SystemExit('Main changed during build; rerun from current main. No deployment performed.')
    run('git', 'config', 'user.name', 'Thabhelo')
    run('git', 'config', 'user.email', 'Thabhelo@users.noreply.github.com')
    run('git', 'add', 'site/public/download/index.html', f'site/public/releases/{name}.dmg', f'site/public/releases/{name}.sha256')
    run('git', 'commit', '-m', f'Publish notarized {name}')
    print('Pushing release to Thabhelo/wand main as Thabhelo', flush=True)
    if run('gh', 'api', 'user', '--jq', '.login', capture=True).stdout.strip() != 'Thabhelo':
        raise SystemExit('Release token must belong to Thabhelo.')
    run('git', 'push', 'origin', 'HEAD:main')

def verify():
    _, build, name = release()
    def get(path):
        req = urllib.request.Request('https://getwand.app/'+path, headers={'User-Agent':'Wand-release-verifier'})
        with urllib.request.urlopen(req, timeout=60) as response: return response.read()
    page = get('download').decode()
    links = DownloadLinks()
    links.feed(page)
    if not re.search(r'\bBuild\s+'+str(build)+r'\b', page) or f'/releases/{name}.dmg' not in links.hrefs:
        raise SystemExit('Download page does not show and link to the expected release.')
    expected = (ROOT/'dist/release'/f'{name}.sha256').read_text().split()[0]
    if hashlib.sha256(get('releases/'+name+'.dmg')).hexdigest() != expected:
        raise SystemExit('Public artifact checksum mismatch')
    print('Published download verified.')

class DownloadLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = set()

    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            href = dict(attrs).get('href')
            if href: self.hrefs.add(href)

if __name__ == '__main__':
    {'validate':validate, 'preflight':preflight, 'preflight-publish':lambda: preflight(publish=True),
     'package':package, 'publish':publish, 'verify':verify}[sys.argv[1]]()
