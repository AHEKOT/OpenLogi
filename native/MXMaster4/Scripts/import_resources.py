#!/usr/bin/env python3
"""Rebuild the native projection from the existing OpenLogi presentation owners."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tomllib

ROOT = Path(__file__).resolve().parents[3]
NATIVE = ROOT / 'native/MXMaster4'
RESOURCES = NATIVE / 'Resources'


def data():
    source = (ROOT / 'crates/openlogi-core/src/binding/action.rs').read_text()
    rows = re.findall(r'^\s+(\w+) "([^"]+)" "([^"]+)" (\w+) \w+,', source, re.M)
    icons_source = (ROOT / 'crates/openlogi-desktop/src/features/binding_editor.rs').read_text()
    icons = {}
    for variants, icon in re.findall(r'((?:Action::\w+(?:\([^)]*\))?\s*\|?\s*)+)\s*=> "action-icons/([^"]+)\.svg"', icons_source):
        for variant in re.findall(r'Action::(\w+)', variants):
            icons[variant] = icon
    if len(rows) != 45 or any(row[0] not in icons for row in rows):
        raise ValueError('Action catalog changed; review the native projection before importing.')
    locales = {}
    for file in (ROOT / 'crates/openlogi-ui/locales').glob('*.toml'):
        value = tomllib.loads(file.read_text())
        locales[file.stem] = {f'{section}.{key}': text for section, entries in value.items()
                             if isinstance(entries, dict) for key, text in entries.items() if isinstance(text, str)}
    defaults = (ROOT / 'crates/openlogi-core/src/binding/defaults.rs').read_text()
    mouse_defaults = dict(re.findall(r'ButtonId::(\w+) => Action::(\w+),', defaults))
    gesture_defaults = dict(re.findall(r'GestureDirection::(\w+) => Action::(\w+),', defaults))
    ring_source = (ROOT / 'crates/openlogi-core/src/binding/action_ring.rs').read_text()
    ring_defaults = re.findall(r'\(Slot::(\w+), Action::(\w+)\)', ring_source)
    thumb_source = (ROOT / 'crates/openlogi-desktop/src/features/mouse/thumbwheel.rs').read_text()
    pairs = re.findall(r'Self::(\w+) =>\s*\{?\s*\(Action::(\w+), Action::(\w+)\)', thumb_source)
    thumb_keys = dict(re.findall(r'Self::(\w+) => "(pointer\.[^"]+)"', thumb_source))
    if len(gesture_defaults) != 5 or len(ring_defaults) != 8 or len(pairs) != 14:
        raise ValueError('Default binding projection changed; review the source.')
    settings = (ROOT / 'crates/openlogi-core/src/config/settings.rs').read_text()
    smartshift = (ROOT / 'crates/openlogi-desktop/src/features/pointer/smartshift.rs').read_text()
    sensitivity = {name.lower(): int(re.search(rf'const SENSITIVITY_{name}: u8 = (\d+);', settings)[1])
                   for name in ['MIN', 'MAX', 'DEFAULT']}
    threshold = {}
    for name, symbol in [('min', 'SMARTSHIFT_MIN_AUTO_DISENGAGE'), ('default', 'SMARTSHIFT_AUTO_DISENGAGE_DEFAULT')]:
        threshold[name] = int(re.search(symbol + r':[^=]+=[\s\S]*?try_new\((\d+)\)', settings)[1])
    threshold['max'] = int(re.search(r'const THRESHOLD_MAX:[^=]+=[\s\S]*?try_new\((\d+)\)', smartshift)[1])
    return {'sensitivity': sensitivity, 'smartShiftThreshold': threshold, 'locales': locales, 'mouseDefaults': mouse_defaults, 'gestureDefaults': gesture_defaults,
            'ringDefaults': [action for _, action in ring_defaults],
            'thumbwheelPresets': [{'id': name, 'key': thumb_keys[name], 'backward': back, 'forward': forward}
                                 for name, back, forward in pairs],
            'actions': [{'id': variant, 'key': key, 'category': category, 'icon': icons[variant]}
                        for variant, _, key, category in rows],
            'themes': json.loads((ROOT / 'crates/openlogi-desktop/themes/openlogi.json').read_text())['themes']}


def generated_files():
    yield RESOURCES / 'presentation.json', (json.dumps(data(), ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()
    catalog = RESOURCES / 'Graphics.xcassets'
    yield catalog / 'Contents.json', b'{"info":{"author":"xcode","version":1}}\n'
    for source in sorted((ROOT / 'crates/openlogi-ui/action-icons').glob('*.svg')):
        folder = catalog / f'ol-{source.stem}.imageset'
        yield folder / source.name, source.read_bytes()
        contents = {'images': [{'filename': source.name, 'idiom': 'universal'}],
                    'info': {'author': 'xcode', 'version': 1},
                    'properties': {'preserves-vector-representation': True, 'template-rendering-intent': 'template'}}
        yield folder / 'Contents.json', (json.dumps(contents, indent=2) + '\n').encode()
    images = []
    for size in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            pixels = size * scale
            source = ROOT / 'design/icon' / ('openlogi.png' if pixels == 1024 else f'openlogi-{pixels}.png')
            images.append({'idiom': 'mac', 'size': f'{size}x{size}', 'scale': f'{scale}x', 'filename': source.name})
            yield catalog / 'AppIcon.appiconset' / source.name, source.read_bytes()
    yield catalog / 'AppIcon.appiconset/Contents.json', (json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2)+'\n').encode()
    yield RESOURCES / 'OpenLogi-Brand-LICENSE.txt', (ROOT / 'design/LICENSE').read_bytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    errors = []
    for path, content in generated_files():
        if args.check:
            if not path.is_file() or path.read_bytes() != content:
                errors.append(str(path.relative_to(NATIVE)))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    provenance = RESOURCES / 'device-provenance.json'
    if provenance.exists():
        for entry in json.loads(provenance.read_text())['files']:
            path = RESOURCES / 'Device' / entry['name']
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
                errors.append('Device/' + entry['name'])
    else:
        errors.append('device-provenance.json')
    if errors:
        raise SystemExit('Resource mismatch: ' + ', '.join(errors))
    print('Presentation, SVGs, application icon and all MX Master 4 assets match their sources.')


if __name__ == '__main__':
    main()
