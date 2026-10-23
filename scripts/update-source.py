#!/usr/bin/env python3
"""Derive AltSource metadata from the actual IPA, never from guessed sizes/versions."""
import argparse
import datetime
import json
import re
from pathlib import Path
from verify_ipa import inspect_ipa


def update_source(ipa, output, repository, tag, notes='', released_at=None):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Repositorio inválido')
    info = inspect_ipa(ipa)
    version = info['CFBundleShortVersionString']
    if tag != f'v{version}':
        raise ValueError('El tag debe coincidir con la versión del IPA')
    source = json.loads(output.read_text()) if output.exists() else {}
    old_app = next((a for a in source.get('apps', []) if a.get('bundleIdentifier') == info['CFBundleIdentifier']), {})
    icon = f'https://raw.githubusercontent.com/{repository}/main/design/identity/pulse/app-icon.png'
    entry = {
        'version': version,
        'buildVersion': info['CFBundleVersion'],
        'date': released_at or datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'localizedDescription': notes,
        'downloadURL': f'https://github.com/{repository}/releases/download/{tag}/Remio.ipa',
        'size': ipa.stat().st_size,
        'minOSVersion': info['MinimumOSVersion'],
    }
    versions = [entry] + [v for v in old_app.get('versions', []) if v['version'] != version]
    versions.sort(key=lambda item: tuple(int(part) for part in item['version'].split('.')), reverse=True)
    source.update(name='Remio · AnubisReal', identifier='com.anubisreal.remio.source',
                  subtitle='Control nativo para tu Portal', website=f'https://github.com/{repository}',
                  iconURL=icon, tintColor='D4D4D4')
    source['apps'] = [{
        'name': 'Remio', 'bundleIdentifier': info['CFBundleIdentifier'], 'developerName': 'AnubisReal',
        'subtitle': 'Mando y herramientas para Portal',
        'localizedDescription': 'Controla tu Portal con trackpad, teclado nativo, aplicaciones y reproducción. Gestiona APK, fotos y copias mediante ADB. Requiere iOS 26 y un Portal compatible en la misma red.',
        'iconURL': icon, 'tintColor': 'D4D4D4', 'category': 'utilities', 'versions': versions,
        'appPermissions': {'entitlements': [], 'privacy': {k: v for k, v in info.items() if k.startswith('NS') and k.endswith('UsageDescription')}},
    }]
    source.setdefault('news', [])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(source, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--ipa', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('distribution/source.json'))
    parser.add_argument('--repository', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--notes', type=Path)
    parser.add_argument('--date')
    args = parser.parse_args()
    update_source(args.ipa, args.output, args.repository, args.tag,
                  args.notes.read_text() if args.notes else '', args.date)
