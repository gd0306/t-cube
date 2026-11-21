#!/usr/bin/env python3
"""Refresh public GitHub release metadata without credentials. Preserve valid data on errors."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import tempfile
import urllib.request

API = 'https://api.github.com/repos/gd0306/t-cube/releases/latest'
PREFIX = 'https://github.com/gd0306/t-cube/releases/download/'

def atomic_write(path, text):
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, prefix='.'+path.name+'.', delete=False) as f:
        temp = Path(f.name)
        try:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        except BaseException:
            try:
                temp.unlink()
            except FileNotFoundError:
                pass
            raise
    os.chmod(temp, 0o644)
    os.replace(temp, path)

def refresh(root):
    request = urllib.request.Request(API, headers={'Accept':'application/vnd.github+json', 'User-Agent':'T-Cube-Product-Site'})
    with urllib.request.urlopen(request, timeout=25) as response:
        raw = response.read(1024*1024+1)
    if len(raw)>1024*1024:
        raise ValueError('Release response is too large')
    release = json.loads(raw)
    tag = release.get('tag_name','')
    if release.get('draft') or release.get('prerelease') or not re.fullmatch(r'v\d+\.\d+\.\d+',tag):
        raise ValueError('Not a stable version')
    version = tag[1:]
    names = [f'T-Cube-{version}-macos-arm64.dmg', f'T-Cube-{version}-windows-x64-setup.exe', 'SHA256SUMS.txt', 'SOURCE_COMMIT.txt']
    assets = []
    for name in names:
        matches=[a for a in release.get('assets',[]) if a.get('name')==name]
        if len(matches)!=1: raise ValueError('Release is missing a required installer or metadata file')
        asset=matches[0]
        url=asset.get('browser_download_url','')
        digest=asset.get('digest','')
        if url!=PREFIX+tag+'/'+name or not isinstance(asset.get('size'),int) or asset['size']<=0 or not re.fullmatch(r'sha256:[a-f0-9]{64}',digest):
            raise ValueError('Invalid release asset')
        assets.append({'name':name,'url':url,'size':asset['size'],'sha256':digest[7:]})
    data={'version':version,'page':'https://github.com/gd0306/t-cube/releases/tag/'+tag,'publishedAt':release.get('published_at'), 'refreshedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(), 'assets':assets}
    html_path=root/'index.html'
    html=html_path.read_text(encoding="utf-8")
    replacements=[(r'https://github\.com/gd0306/t-cube/releases/download/v\d+\.\d+\.\d+/T-Cube-\d+\.\d+\.\d+-macos-arm64\.dmg',assets[0]['url']), (r'https://github\.com/gd0306/t-cube/releases/download/v\d+\.\d+\.\d+/T-Cube-\d+\.\d+\.\d+-windows-x64-setup\.exe',assets[1]['url']), (r'https://github\.com/gd0306/t-cube/releases/download/v\d+\.\d+\.\d+/SHA256SUMS\.txt',assets[2]['url'])]
    for pattern,replacement in replacements:
        html,count=re.subn(pattern,replacement,html)
        if count<1:raise ValueError('Fallback download markup is missing')
    html,count=re.subn(r'(data-version>)v\d+\.\d+\.\d+',lambda m:m[1]+tag,html)
    if count!=1:raise ValueError('Version label markup is missing')
    for platform,asset in [('macos',assets[0]),('windows',assets[1])]:
        html,count=re.subn(r'(data-size="'+platform+r'">)[^<]+',lambda m:m[1]+f'{asset["size"]/1048576:.1f} MB',html)
        if count!=1:raise ValueError('Size label markup is missing')
    atomic_write(root/'release.json',json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    if html!=html_path.read_text(encoding="utf-8"):atomic_write(html_path,html)
    print('Verified stable release '+tag+'; updated installer links and metadata.')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True);args=parser.parse_args()
    try:refresh(args.root)
    except Exception as error:
        print('Release refresh failed; previous valid downloads retained: '+str(error))
        raise SystemExit(1)
