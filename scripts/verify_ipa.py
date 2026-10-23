#!/usr/bin/env python3
"""Validate the distributable, including device architecture and privacy metadata."""
import argparse
import json
import plistlib
import struct
import zipfile
from pathlib import Path


def inspect_ipa(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        plist_paths = [n for n in names if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        if len(plist_paths) != 1:
            raise ValueError('Se esperaba una única aplicación en Payload')
        root = plist_paths[0].removesuffix('Info.plist')
        info = plistlib.loads(archive.read(plist_paths[0]))
        if info.get('CFBundleIdentifier') != 'com.remio.app':
            raise ValueError('Bundle identifier incorrecto')
        if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
            raise ValueError('El IPA debe ser para un dispositivo, no para simulador')
        binary = archive.read(root + info['CFBundleExecutable'])
        if len(binary) < 32 or struct.unpack_from('<II', binary) != (0xFEEDFACF, 0x0100000C):
            raise ValueError('Se esperaba un ejecutable Mach-O arm64')
        offset = 32
        device_platform = False
        for _ in range(struct.unpack_from('<I', binary, 16)[0]):
            command, size = struct.unpack_from('<II', binary, offset)
            if size < 8 or offset + size > len(binary):
                raise ValueError('Mach-O inválido')
            if command == 0x32 and size >= 24:
                device_platform = struct.unpack_from('<I', binary, offset + 8)[0] == 2
            offset += size
        if not device_platform:
            raise ValueError('El ejecutable no declara plataforma iOS física')
        for name in names:
            if name.endswith(('.mobileprovision', '.p12', '.pem', '.key')) or name.startswith(('app/', 'gradle/', 'references/')):
                raise ValueError('Contenido privado o de referencia dentro del IPA')
        if not any(n.startswith(root) and n.endswith('.png') and 'AppIcon' in n for n in names):
            raise ValueError('Falta el icono compilado')
        if archive.testzip():
            raise ValueError('CRC incorrecto')
        return info


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa', type=Path)
    args = parser.parse_args()
    info = inspect_ipa(args.ipa)
    print(json.dumps({k: info[k] for k in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion', 'MinimumOSVersion')}, ensure_ascii=False))
