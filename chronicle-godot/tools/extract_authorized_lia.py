"""Extract a selected, attributed art subset from the user-authorized local APK.

Index/contact sheets stay in ignored work. Only explicitly selected Sprite IDs
enter art/licensed_temporary; no APK executable or middleware is run or copied.
Requires the existing research UnityPy/Pillow environment.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
APK = Path('C:/soft/wxlog/xwechat_files/wxid_218v9z9ee65n22_662a/msg/file/2026-09/base.apk.1')
WORK = ROOT / 'work/adventure-rework/licensed-art'
ART = ROOT / 'chronicle-godot/art'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--select', nargs='*', default=[], help='Sprite path IDs explicitly chosen after preview')
    parser.add_argument('--preview-prefix', nargs='*', default=['drawing_', 'Place_'])
    args = parser.parse_args()
    expected = '4e1a32ed5c6d261a5def62de2a26bb9b37af752775ba82f47e12b2b0ff8e36d8'
    if hashlib.sha256(APK.read_bytes()).hexdigest() != expected:
        raise ValueError('Source APK differs from the reviewed version; re-index and review before extraction')
    WORK.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(APK) as archive:
        env = UnityPy.load(archive.read('assets/bin/Data/data.unity3d'))
    rows, selected, previews = [], [], []
    for obj in env.objects:
        if obj.type.name != 'Sprite':
            continue
        sprite = obj.read()
        rect = sprite.m_Rect
        row = {'id': obj.path_id, 'file': obj.assets_file.name, 'name': sprite.m_Name,
               'width': rect.width, 'height': rect.height}
        rows.append(row)
        if str(obj.path_id) in args.select:
            selected.append((row, sprite.image))
        elif not args.select and any(sprite.m_Name.startswith(prefix) for prefix in args.preview_prefix):
            previews.append((row, sprite.image))
    (WORK / 'sprites.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
    for page in range(0, len(previews), 60):
        sheet = Image.new('RGB', (1000, 12 * 112), '#202322')
        draw = ImageDraw.Draw(sheet)
        for n, (row, original) in enumerate(previews[page:page + 60]):
            image = original.convert('RGBA')
            image.thumbnail((190, 84), Image.Resampling.NEAREST)
            x, y = (n % 5) * 200, (n // 5) * 112
            sheet.paste(image, (x, y), image)
            draw.text((x, y + 86), str(row['id']) + ' ' + row['name'][:22], fill='white')
        sheet.save(WORK / f'sheet-{page // 60:02}.png')
    if args.select:
        if len(selected) != len(set(args.select)):
            raise ValueError('A selected Sprite ID is missing or ambiguous; no runtime files written')
        destination = ART / 'licensed_temporary/life_in_adventure'
        destination.mkdir(parents=True, exist_ok=True)
        catalog_path = ART / 'catalog.json'
        catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
        for row, image in selected:
            path = destination / f"sprite_{row['id']}.png"
            image.save(path)
            relative = path.relative_to(ART).as_posix()
            catalog['files'] = [entry for entry in catalog['files'] if entry['path'] != relative]
            catalog['files'].append({'path': relative, 'status': 'runtime', 'visual_style': 'pixel_art',
                'source': '', 'provenance': 'licensed_temporary/life_in_adventure/PROVENANCE.md',
                'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'width': image.width, 'height': image.height, 'temporary': True,
                'attribution': 'StudioWheel / Life in Adventure 1.2.23', 'source_object': row,
                'authorization': 'user_confirmed_2026-09-28', 'replacement_required': True})
        catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'sprites': len(rows), 'previewed': len(previews), 'selected': [r for r, _ in selected]}))


if __name__ == '__main__':
    main()
