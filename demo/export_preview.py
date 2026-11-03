#!/usr/bin/env python3
"""Build optional whole-map previews from this demo's matching local exports.

    .venv/bin/python demo/export_preview.py

Uses only exported coarse ground and minimap images; never invents missing terrain.
The preview is for display only, not elevation inspection or collision.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct

from PIL import Image


def simplify(data, key, stride=4):
    magic, nv, ni = struct.unpack_from('<4sII', data)
    if magic != b'MMT1' or len(data) != 12 + nv*12 + ni*4 or nv % 4 or ni != nv//4*6:
        raise ValueError('Expected exported coarse quad mesh')
    col, row = divmod(key, 64)
    points, cells = {}, set()
    vertices = list(struct.iter_unpack('<3f', data[12:12+nv*12]))
    for start in range(0, nv, 4):
        quad = vertices[start:start+4]
        grid = [(round((x-col)*16), round((y-row)*16)) for x,y,_ in quad]
        cells.add(grid[0])
        points.update(zip(grid,quad))
    out, indices, used = [], [], {}
    def emit(x,y,size):
        if not all((cx,cy) in cells for cy in range(y,y+size) for cx in range(x,x+size)):
            # Refine around holes instead of turning one absent chunk into a
            # large missing square. The final hole matches the source mesh.
            if size > 1:
                half = size//2
                for dx,dy in [(0,0),(half,0),(half,half),(0,half)]:
                    emit(x+dx,y+dy,half)
            return
        corners = [(x,y),(x+size,y),(x+size,y+size),(x,y+size)]
        for corner in corners:
            if corner not in used:
                used[corner] = len(out)
                out.append(points[corner])
        indices.extend(used[corners[i]] for i in (0,1,2,0,2,3))
    for y in range(0,16,stride):
        for x in range(0,16,stride):
            emit(x,y,stride)
    return out, indices


def build_preview(folder, images, metadata):
    if not metadata['tiles']:
        return None
    vertices, indices, ranges = [], [], []
    for tile in metadata['tiles']:
        points, faces = simplify((folder/tile['lods']['coarse']).read_bytes(),tile['key'])
        ranges.append(dict(key=tile['key'],offset=len(indices),count=len(faces)))
        indices.extend(len(vertices)+i for i in faces)
        vertices.extend(points)
    if not indices:
        return None
    mesh = struct.pack('<4sII',b'MMT1',len(vertices),len(indices))
    mesh += b''.join(struct.pack('<3f',*v) for v in vertices)
    mesh += struct.pack(f'<{len(indices)}I',*indices)
    # Content-addressed files let a deployed manifest change without reusing a
    # browser-cached overview whose index ranges belong to the previous mesh.
    mesh_name = f'preview-{hashlib.sha256(mesh).hexdigest()[:12]}.mmt'
    (folder/mesh_name).write_bytes(mesh)
    keys = [divmod(t['key'],64) for t in metadata['tiles']]
    bounds = [min(c for c,r in keys),min(r for c,r in keys),max(c for c,r in keys)+1,max(r for c,r in keys)+1]
    result = dict(mesh=mesh_name,bounds=bounds,tiles=ranges)
    image_manifest = images/'manifest.json'
    if image_manifest.is_file():
        source = json.loads(image_manifest.read_text())
        if any(source.get(k) != metadata.get(k) for k in ('product','version','inst')):
            raise ValueError('Preview imagery must match the terrain product, build and map')
        atlas = Image.new('RGB',((bounds[2]-bounds[0])*32,(bounds[3]-bounds[1])*32),(60,85,65))
        for tile in metadata['tiles']:
            path = images/'64'/f"{tile['key']}.webp"
            if not path.is_file():
                path = images/f"{tile['key']}.webp"
            if path.is_file():
                c,r = divmod(tile['key'],64)
                with Image.open(path) as picture:
                    atlas.paste(picture.convert('RGB').resize((32,32),Image.Resampling.LANCZOS),((c-bounds[0])*32,(r-bounds[1])*32))
        output = io.BytesIO()
        atlas.save(output,format='WEBP',quality=75,method=6)
        picture = output.getvalue()
        image_name = f'preview-{hashlib.sha256(picture).hexdigest()[:12]}.webp'
        (folder/image_name).write_bytes(picture)
        result['image'] = image_name
    return result


def main():
    from export_terrain import compatible, load_atlas
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--terrain',type=Path,default=root/'terrain')
    parser.add_argument('--tiles',type=Path,default=root/'tiles')
    parser.add_argument('--inst',type=int,action='append')
    args = parser.parse_args()
    _, atlas = load_atlas()
    for path in sorted(args.terrain.glob('*/manifest.json')):
        metadata = json.loads(path.read_text())
        if args.inst and metadata['inst'] not in args.inst:
            continue
        if metadata.get('format') != 'magicmap-terrain-v1':
            raise ValueError('Unsupported terrain format')
        compatible(metadata['product'],metadata['version'],atlas)
        preview = build_preview(path.parent,args.tiles/str(metadata['inst']),metadata)
        if preview:
            metadata['preview'] = preview
            tmp = path.with_suffix('.json.tmp')
            tmp.write_text(json.dumps(metadata,separators=(',',':'))+'\n')
            tmp.replace(path)
            print(f"Map {metadata['inst']}: preview of {len(preview['tiles'])} tiles",flush=True)


if __name__ == '__main__':
    main()
