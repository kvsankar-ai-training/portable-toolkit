"""Build the portable-toolkit release ZIPs from a git tag.

    uv run tools/build_release.py regular <tag> <out.zip>
    uv run tools/build_release.py offline <regular.zip> <wheel-source> <out.zip>

regular packs the participant files of <tag> under portable-toolkit/. The
files come from `git archive`, which applies .gitattributes, so the result
does not depend on how this checkout was made. Every entry carries the date of
the tagged commit, so the same tag gives the same ZIP.

offline adds portable-toolkit/offline-wheels/win_amd64-cp313/ to a regular
ZIP. <wheel-source> is either `pypi`, to download the wheels named in the
ZIP's own toolkit/offline-win313.sha256, or a previous offline ZIP to reuse
its wheels. Either way every wheel must match that hash list, and the set of
wheels must equal it exactly.

Standard library only; it also runs as plain `python3` where uv is absent.
"""
import hashlib
import io
import json
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import PurePosixPath

PREFIX = 'portable-toolkit/'
# Everything else in the repo (README.md, tests, tools, docs, git files) is
# for maintainers, not participants.
PARTICIPANT_FILES = ('GUI.cmd', 'README.txt', 'SETUP.cmd', 'SKILL.md', 'toolkit/')
WHEELS = PREFIX + 'offline-wheels/win_amd64-cp313/'
HASH_LIST = PREFIX + 'toolkit/offline-win313.sha256'
LOCK = PREFIX + 'toolkit/offline-win313.lock'


def add(z, name, data, stamp):
    info = zipfile.ZipInfo(name, stamp)
    info.external_attr = 0o644 << 16
    # Wheels are already compressed.
    info.compress_type = zipfile.ZIP_STORED if name.endswith('.whl') else zipfile.ZIP_DEFLATED
    z.writestr(info, data)


def git(*args):
    return subprocess.run(['git', *args], capture_output=True, check=True).stdout


def regular(tag, out):
    # The commit's own calendar date, in the timezone it was made in.
    date = git('log', '-1', '--format=%cd', '--date=format:%Y %m %d', tag).decode().split()
    stamp = (int(date[0]), int(date[1]), int(date[2]), 0, 0, 0)
    files = {}
    with tarfile.open(fileobj=io.BytesIO(git('archive', '--format=tar', tag))) as tar:
        for member in tar.getmembers():
            if member.isfile() and member.name.startswith(PARTICIPANT_FILES):
                files[member.name] = tar.extractfile(member).read()
    if 'toolkit/install.ps1' not in files:
        sys.exit(f'{tag} has no toolkit/install.ps1')
    with zipfile.ZipFile(out, 'w') as z:
        for name in sorted(files):
            add(z, PREFIX + name, files[name], stamp)
    print(f'{out}: {len(files)} files from {tag}, dated {stamp[:3]}')


def pypi_wheels(lock, expected):
    # The lock pins name==version; the hash list names the exact files.
    wheels = {}
    for line in lock.splitlines():
        if '==' not in line or line.startswith('#'):
            continue
        name, version = line.strip().split('==')
        with urllib.request.urlopen(f'https://pypi.org/pypi/{name}/{version}/json', timeout=60) as r:
            release = json.load(r)
        for f in release['urls']:
            if f['filename'] in expected:
                with urllib.request.urlopen(f['url'], timeout=300) as r:
                    wheels[f['filename']] = r.read()
    return wheels


def zip_wheels(path):
    with zipfile.ZipFile(path) as z:
        return {PurePosixPath(n).name: z.read(n)
                for n in z.namelist() if n.startswith(WHEELS) and n.endswith('.whl')}


def offline(regular_zip, wheel_source, out):
    with zipfile.ZipFile(regular_zip) as reg:
        entries = [(i, reg.read(i)) for i in reg.infolist()]
    contents = {i.filename: data for i, data in entries}
    expected = {}
    for line in contents[HASH_LIST].decode().splitlines():
        digest, name = line.split('  ')
        expected[name] = digest.lower()
    wheels = (pypi_wheels(contents[LOCK].decode(), expected) if wheel_source == 'pypi'
              else zip_wheels(wheel_source))
    if set(wheels) != set(expected):
        sys.exit(f'wheels differ from the hash list: {sorted(set(wheels) ^ set(expected))}')
    for name, data in wheels.items():
        if hashlib.sha256(data).hexdigest() != expected[name]:
            sys.exit(f'hash mismatch: {name}')
    stamp = entries[0][0].date_time
    with zipfile.ZipFile(out, 'w') as z:
        for info, data in entries:
            add(z, info.filename, data, info.date_time)
        add(z, PREFIX + 'offline-wheels/', b'', stamp)
        for name in sorted(wheels):
            add(z, WHEELS + name, wheels[name], stamp)
    print(f'{out}: {len(wheels)} wheels verified against the hash list')


if __name__ == '__main__':
    commands = {'regular': regular, 'offline': offline}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]](*sys.argv[2:])
