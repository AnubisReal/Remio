"""Keep both native catalogs complete and interpolation-compatible."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / 'ios/Remio/Resources'


def units(localization):
    if 'stringUnit' in localization:
        yield localization['stringUnit']
    for variants in localization.get('variations', {}).values():
        for variant in variants.values():
            yield from units(variant)


def placeholders(value):
    return sorted(re.findall(r'%(?:\d+\$)?(?:lld|ld|lu|llu|@|d|u|f)', value))


class LocalizationTests(unittest.TestCase):
    def test_all_catalog_entries_have_spanish_and_english(self):
        for file in RESOURCES.glob('*.xcstrings'):
            catalog = json.loads(file.read_text())
            self.assertEqual(catalog['sourceLanguage'], 'es')
            for key, entry in catalog['strings'].items():
                for language in ('es', 'en'):
                    with self.subTest(file=file.name, key=key, language=language):
                        localized = entry['localizations'][language]
                        variants = list(units(localized))
                        self.assertTrue(variants)
                        for unit in variants:
                            self.assertEqual(unit['state'], 'translated')
                            self.assertTrue(unit['value'].strip())

    def test_translations_preserve_interpolated_arguments(self):
        catalog = json.loads((RESOURCES / 'Localizable.xcstrings').read_text())
        for key, entry in catalog['strings'].items():
            for language in ('es', 'en'):
                for unit in units(entry['localizations'][language]):
                    with self.subTest(key=key, language=language):
                        self.assertEqual(placeholders(key), placeholders(unit['value']))

    def test_count_labels_have_native_plural_variants(self):
        strings = json.loads((RESOURCES / 'Localizable.xcstrings').read_text())['strings']
        for key in ('Enviar %lld fotos', 'Enviar %lld imágenes', 'Crear copia · %lld apps', '%lld APK'):
            for language in ('es', 'en'):
                plural = strings[key]['localizations'][language]['variations']['plural']
                self.assertEqual(set(plural), {'one', 'other'})

    def test_privacy_description_matches_base_info_plist(self):
        import plistlib
        info = plistlib.loads((ROOT / 'ios/Configuration/Info.plist').read_bytes())
        strings = json.loads((RESOURCES / 'InfoPlist.xcstrings').read_text())['strings']
        for key, value in info.items():
            if key.startswith('NS') and key.endswith('UsageDescription'):
                self.assertEqual(strings[key]['localizations']['es']['stringUnit']['value'], value)


if __name__ == '__main__':
    unittest.main()
