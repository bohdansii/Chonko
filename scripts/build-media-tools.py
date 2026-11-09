#!/usr/bin/env python3
"""Rebuild the exact bundled ARM64 tools from pinned official sources. Requires Xcode CLI tools."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request

project = Path(__file__).resolve().parent.parent
root = project / '.work/media'
root.mkdir(parents=True, exist_ok=True)
manifest = json.loads((project / 'scripts/media-sources.json').read_text())
for name, item in manifest.items():
    archive = root / item['archive']
    if not archive.exists():
        print('Downloading', name, flush=True)
        request = urllib.request.Request(item['url'], headers={'User-Agent': 'Chonko-build'})
        with urllib.request.urlopen(request, timeout=120) as response, archive.open('wb') as output:
            shutil.copyfileobj(response, output)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != item['sha256']:
        raise SystemExit('Source checksum mismatch: ' + name)
    destination = root / name
    destination.mkdir(exist_ok=True)
    if not any(destination.iterdir()):
        with tarfile.open(archive) as bundle:
            for member in bundle.getmembers():
                target = (destination / member.name).resolve()
                if destination.resolve() not in target.parents:
                    raise SystemExit('Unsafe archive entry')
                if member.issym() or member.islnk():
                    linked = (target.parent / member.linkname).resolve()
                    if destination.resolve() not in linked.parents:
                        raise SystemExit('Unsafe archive link')
            bundle.extractall(destination)
for script in ['build-video-tools.sh', 'build-ghostscript.sh', 'build-qpdf-tools.sh']:
    subprocess.run(['bash', str(project / 'scripts' / script)], cwd=project, check=True)
codecs = project / 'Resources/Codecs'
codecs.mkdir(parents=True, exist_ok=True)
for name in ['ffmpeg', 'ffprobe']:
    shutil.copy2(root / 'prefix/bin' / name, codecs / name)
shutil.copy2(root / 'qpdf-build/qpdf/qpdf', codecs / 'qpdf')
shutil.copy2(root / 'ghostscript/ghostscript-10.08.0/bin/gs', codecs / 'gs')
shutil.copytree(root / 'ghostscript/ghostscript-10.08.0/Resource/Font', codecs / 'Ghostscript/Resource/Font', dirs_exist_ok=True)
for name in ['cwebp', 'dwebp']:
    shutil.copy2(root / 'webpBinary/libwebp-1.6.0-mac-arm64/bin' / name, codecs / name)
print('Media tools rebuilt for macOS 26.0+. WebP uses the pinned official Google ARM64 distribution.')
