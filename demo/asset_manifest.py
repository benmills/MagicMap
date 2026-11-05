"""Demo-only asset metadata. Never infer compatibility from a filename or major version."""
from pathlib import Path
import json
import math

FORMATS = {'terrain': 'magicmap-terrain-v1', 'objects': 'magicmap-objects-v1'}


def manifest(root, kind, inst, product, version):
    path = Path(root) / kind / str(inst) / 'manifest.json'
    result = {'available': False, 'reason': f'{kind.capitalize()} assets are not installed.'}
    if not path.is_file():
        return result
    try:
        data = json.loads(path.read_text())
        if data.get('product') != product or data.get('version') != version:
            return dict(result, reason=f'{kind.capitalize()} build mismatch: expected {product} {version}, '
                        f'found {data.get("product")} {data.get("version")}.')
        if data.get('format') != FORMATS[kind] or data.get('inst') != inst:
            return dict(result, reason=f'Unsupported {kind} format or map ID. Convert the assets before use.')
        tiles = data.get('tiles')
        if not isinstance(tiles, list) or not tiles or len(tiles) > 4096:
            raise ValueError('empty or invalid tile index')
        keys = set()
        for tile in tiles:
            key = tile['key']
            if not isinstance(key, int) or not 0 <= key < 4096 or key in keys:
                raise ValueError('invalid or duplicate tile key')
            keys.add(key)
            if kind == 'terrain':
                if not all(isinstance(tile.get(k), (float,int)) and math.isfinite(tile[k]) and abs(tile[k]) < 100000 for k in ('min','max')) or tile['min'] > tile['max']:
                    raise ValueError('invalid elevation bounds')
            files = list(tile['lods'].values()) if kind == 'terrain' else [tile['file']]
            if not files:
                raise ValueError('empty tile')
            if kind == 'terrain' and 'coarse' not in tile['lods']:
                raise ValueError('coarse mesh is required for full-map coverage')
            for rel in files:
                if not isinstance(rel, str) or Path(rel).is_absolute() or '..' in Path(rel).parts:
                    raise ValueError('invalid asset path')
                if not (path.parent / rel).resolve().is_relative_to(path.parent.resolve()):
                    raise ValueError('asset path escapes map directory')
                if not (path.parent / rel).is_file():
                    raise ValueError(f'missing {rel}')
        return {'available': True, 'manifest': f'/{kind}/{inst}/manifest.json', 'data': data,
                'reason': f'{len(tiles)}/{data.get("expectedTiles", len(tiles))} tiles · {product} {version}'}
    except (OSError, ValueError, TypeError, KeyError) as e:
        return dict(result, reason=f'Invalid {kind} manifest: {e}')


def inventory(root, inst, product, version):
    tile_dir = Path(root) / 'tiles' / str(inst)
    keys = sorted(int(p.stem) for p in tile_dir.glob('*.webp') if p.stem.isdecimal())
    tile_reason = 'Legacy imagery: no build manifest' if keys else 'Map images are not installed.'
    if (tile_dir/'manifest.json').is_file():
        try:
            metadata=json.loads((tile_dir/'manifest.json').read_text())
            if (metadata.get('product'),metadata.get('version'),metadata.get('inst')) != (product,version,inst):
                keys=[]
                tile_reason='Map image build mismatch; regenerate the tiles.'
            else:
                tile_reason=f'{len(keys)} images · {product} {version}'
        except (OSError,ValueError,TypeError):
            keys=[]
            tile_reason='Invalid image manifest; regenerate the tiles.'
    return {'product': product, 'version': version, 'tiles': keys, 'tileReason': tile_reason,
            'blocks': bool(keys) and (tile_dir / 'b8').is_dir(),  # (demo/export_blocks.py's quick copies)
            **{kind: manifest(root, kind, inst, product, version) for kind in FORMATS}}
