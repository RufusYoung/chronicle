"""Deploy only Chronicle's allowlisted snapshot and private read-only gateway."""
import argparse
import datetime
import io
import json
import pathlib
import shlex
import subprocess
import tarfile

ROOT = pathlib.Path(__file__).resolve().parent
REPO = ROOT.parent
WORK = REPO / 'work/mcp'
HOST = 'yiwenzhi@120.27.141.243'
KEY = pathlib.Path.home() / '.ssh/yiwenzhi_ecs_rsa'
BASE = '/home/yiwenzhi/chronicle-mcp'
PRIVATE = f'{BASE}/private'
CADDY_SOURCE = '/home/yiwenzhi/current/deploy/Caddyfile.ip-public'
WEB = 'deploy-web-1'
SSH = ['ssh', '-o', 'BatchMode=yes', '-i', str(KEY), HOST]
SCP = ['scp', '-q', '-i', str(KEY)]


def remote(command):
    return subprocess.check_output([*SSH, command], text=True, encoding='utf-8')


def upload(source, destination):
    subprocess.run([*SCP, str(source), f'{HOST}:{destination}'], check=True)


def configure_proxy(release):
    live = remote(f'sudo -n docker exec {WEB} cat /etc/caddy/Caddyfile')
    source = remote(f'cat {CADDY_SOURCE}')
    if live != source:
        raise RuntimeError('Caddy source and live config differ; refusing to overwrite either')
    if '@chronicleMcp' in live:
        return
    marker = ' @vibeMcp path '
    if marker not in live or '@originalApp not path ' not in live:
        raise RuntimeError('Unknown Caddy layout; no automatic replacement')
    paths = '/chronicle-mcp /chronicle-mcp/* /.well-known/oauth-authorization-server/chronicle-mcp /.well-known/oauth-protected-resource/chronicle-mcp/mcp'
    route = f' @chronicleMcp path {paths}\n handle @chronicleMcp {{\n  reverse_proxy chronicle-mcp:8792\n }}\n\n'
    proposed = live.replace(marker, route + marker, 1).replace('@originalApp not path ', f'@originalApp not path {paths} ', 1)
    candidate = WORK / 'Caddyfile.proposed'
    candidate.write_text(proposed, encoding='utf-8', newline='\n')
    upload(candidate, f'{release}/Caddyfile.proposed')
    remote(f'sudo -n docker cp {release}/Caddyfile.proposed {WEB}:/tmp/Caddyfile.chronicle')
    remote(f'sudo -n docker exec {WEB} caddy validate --config /tmp/Caddyfile.chronicle --adapter caddyfile')
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d%H%M%S')
    backup = f'{CADDY_SOURCE}.before-chronicle-{stamp}'
    remote(f'cp {CADDY_SOURCE} {backup}')
    # Recheck before changing shared routing; another deployment may have intervened.
    if remote(f'sudo -n docker exec {WEB} cat /etc/caddy/Caddyfile') != live:
        raise RuntimeError('Concurrent Caddy change; candidate not installed')
    try:
        remote(f'cp {release}/Caddyfile.proposed {CADDY_SOURCE}')
        remote(f'sudo -n docker cp {release}/Caddyfile.proposed {WEB}:/etc/caddy/Caddyfile')
        remote(f'sudo -n docker exec {WEB} caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile')
    except Exception:
        remote(f'cp {backup} {CADDY_SOURCE}')
        remote(f'sudo -n docker cp {backup} {WEB}:/etc/caddy/Caddyfile')
        remote(f'sudo -n docker exec {WEB} caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile')
        raise
    print('Caddy route installed; original config backup retained on server.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--private', default='C:/code/game/chronicle-private/mcp')
    parser.add_argument('--configure-proxy', action='store_true')
    args = parser.parse_args()
    private = pathlib.Path(args.private).resolve()
    if private.is_relative_to(REPO):
        raise RuntimeError('Credentials must be outside the repository')
    status = subprocess.check_output(['git', 'status', '--porcelain', '--', 'mcp'], cwd=REPO, text=True)
    if status.strip():
        raise RuntimeError('Commit and verify MCP source before deploying')
    WORK.mkdir(parents=True, exist_ok=True)
    snapshot_path = WORK / 'snapshot.json'
    subprocess.run(['node', str(ROOT / 'snapshot.mjs'), str(snapshot_path)], check=True, cwd=REPO)
    snapshot = json.loads(snapshot_path.read_text(encoding='utf-8'))
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d%H%M%S')
    release = f'{BASE}/releases/{snapshot["commit"][:12]}-{stamp}'
    names = ['auth.mjs', 'server.mjs', 'catalog.mjs', 'tools.mjs', 'package.json', 'package-lock.json', 'Dockerfile', 'compose.yml', '.dockerignore']
    archive = WORK / 'gateway.tar.gz'
    with tarfile.open(archive, 'w:gz') as tar:
        for name in names:
            tar.add(ROOT / name, arcname=name)
        tar.add(snapshot_path, arcname='snapshot.json')
        compose_env = f'CHRONICLE_ENV_FILE={PRIVATE}/gateway.env\nCHRONICLE_DATA_DIR={PRIVATE}/data\n'.encode()
        entry = tarfile.TarInfo('compose.env'); entry.size = len(compose_env)
        tar.addfile(entry, io.BytesIO(compose_env))
    remote(f'install -d -m 700 {release} {PRIVATE} {PRIVATE}/data')
    upload(archive, f'{release}/gateway.tar.gz')
    # Only the scrypt hash is uploaded; plaintext password stays on Windows.
    upload(private / 'gateway.env', f'{PRIVATE}/gateway.env')
    remote(f'chmod 600 {PRIVATE}/gateway.env')
    if remote(f'stat -c %u:%g {PRIVATE}/data').strip() != '1000:1000':
        raise RuntimeError('OAuth data must be owned by container uid/gid 1000; refusing to broaden permissions')
    remote(f'tar -xzf {release}/gateway.tar.gz -C {release}')
    result = remote(f'sudo -n docker compose --env-file {release}/compose.env -p chronicle-mcp -f {release}/compose.yml up -d --build')
    print(result)
    if args.configure_proxy:
        configure_proxy(release)
    remote(f'ln -sfn {shlex.quote(release)} {BASE}/current')
    (WORK / 'deployment.json').write_text(json.dumps({'commit':snapshot['commit'],'release':release,'deployedAt':stamp},indent=2),encoding='utf-8')
    print('Deployed. Run npm run check:public before calling it available.')


if __name__ == '__main__':
    main()
