"""Asset compatibility and native terrain geometry: no game install needed."""
import json
from pathlib import Path
import struct
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'demo'))
sys.path.insert(0, str(ROOT/'tools'))
import asset_manifest
import export_terrain
import export_preview
import export_icons
import server


def chunk(tag, data):
    return tag[::-1] + struct.pack('<I', len(data)) + data


def adt(mask=0, high=False, missing_heights=False):
    header = bytearray(128)
    struct.pack_into('<III', header, 0, 0x10000 if high else 0, 0, 0)
    struct.pack_into('<f', header, 0x70, 25)
    struct.pack_into('<Q' if high else '<H', header, 0x14 if high else 0x3c, mask)
    return chunk(b'MCNK', header + (b'' if missing_heights else chunk(b'MCVT', struct.pack('<145f', *range(145)))))


def test_native_fans_and_holes():
    vertices, indices = export_terrain.mesh(adt(), 32*64+48)
    assert len(vertices) == 145 and len(indices) == 64*12
    assert vertices[0] == (32, 48, 25)
    assert vertices[9] == (32+.5/128, 48+.5/128, 34)
    assert indices[:12] == [0, 1, 9, 1, 18, 9, 18, 17, 9, 17, 0, 9]
    assert len(export_terrain.mesh(adt(1, True), 0)[1]) == 63*12
    assert len(export_terrain.mesh(adt(1), 0)[1]) == 60*12
    assert export_terrain.mesh(adt(1), 0, coarse=True) == ([], [])
    assert export_terrain.mesh(adt(missing_heights=True), 0) == ([], [])


def test_binary_header(tmp_path):
    vertices, faces = export_terrain.mesh(adt(), 0)
    file = tmp_path/'ground.mmt'
    export_terrain.write_mesh(file, vertices, faces)
    data = file.read_bytes()
    assert struct.unpack_from('<4sII', data) == (b'MMT1', 145, 768)
    assert len(data) == 12 + len(vertices)*12 + len(faces)*4


def test_source_build_is_exact():
    export_terrain.compatible('wow_classic_beta', '1.60.1.70450', server.Atlas)
    for product, version in [('wow_classic_era', '1.60.1.70450'), ('wow_classic_beta', '1.60.2.80000')]:
        with pytest.raises(ValueError):
            export_terrain.compatible(product, version, server.Atlas)


def test_preview_simplifies_ground_without_filling_missing_chunks(tmp_path):
    points, faces = [], []
    for y in range(16):
        for x in range(16):
            faces.extend(len(points)+i for i in (0,1,2,0,2,3))
            points.extend((vx/16,vy/16,vx*10) for vx,vy in [(x,y),(x+1,y),(x+1,y+1),(x,y+1)])
    path = tmp_path/'coarse.mmt'
    export_terrain.write_mesh(path,points,faces)
    reduced, indices = export_preview.simplify(path.read_bytes(),0)
    assert len(reduced) == 25 and len(indices) == 16*6
    assert (1,1,160) in reduced
    # The first absent source chunk must also be absent in the visual preview.
    export_terrain.write_mesh(path,points[4:],[i-4 for i in faces[6:]])
    reduced, indices = export_preview.simplify(path.read_bytes(),0)
    assert len(indices) == 21*6
    assert (0,0,0) not in reduced and (1/16,0,10) in reduced
    metadata = dict(product='wow_classic_beta',version='1.60.1.70450',inst=0,
                    tiles=[dict(key=0,lods=dict(coarse='coarse.mmt'))])
    preview = export_preview.build_preview(tmp_path,tmp_path/'missing-images',metadata)
    assert preview['tiles'] == [dict(key=0,offset=0,count=21*6)]
    assert preview['bounds'] == [0,0,1,1]
    assert 'image' not in preview
    images = tmp_path/'images'
    images.mkdir()
    (images/'manifest.json').write_text(json.dumps(dict(product='wow_classic_beta',version='1.60.2.0',inst=0)))
    with pytest.raises(ValueError,match='match'):
        export_preview.build_preview(tmp_path,images,metadata)


def test_manifest_missing_mismatch_and_partial_files(tmp_path):
    args = (tmp_path, 'terrain', 0, 'wow_classic_beta', '1.60.1.70450')
    assert not asset_manifest.manifest(*args)['available']
    folder = tmp_path/'terrain'/'0'
    folder.mkdir(parents=True)
    data = dict(format='magicmap-terrain-v1', inst=0, product='wow_classic_beta', version='1.60.0',
                tiles=[dict(key=1, min=0,max=1,lods=dict(coarse='1.mmt'))])
    (folder/'manifest.json').write_text(json.dumps(data))
    assert 'mismatch' in asset_manifest.manifest(*args)['reason']
    data['version'] = '1.60.1.70450'
    (folder/'manifest.json').write_text(json.dumps(data))
    assert 'missing 1.mmt' in asset_manifest.manifest(*args)['reason']
    (folder/'1.mmt').write_bytes(b'mesh checked by client parser')
    assert asset_manifest.manifest(*args)['available']
    data['tiles'][0]['lods']['coarse'] = '../../outside'
    (folder/'manifest.json').write_text(json.dumps(data))
    assert not asset_manifest.manifest(*args)['available']


def test_all_maps_have_fittable_bounds_and_places_are_searchable():
    maps = server.maps({})
    assert len(maps) >= 43
    assert any(m['uiMapID'] is None for m in maps)
    assert all(m['bounds'][0] < m['bounds'][2] and m['bounds'][1] < m['bounds'][3] for m in maps)
    assert any(r['kind'] == 'map' and r['inst'] == 1 for r in server.find({'q': 'Kalimdor'}))
    assert any(r['kind'] == 'place' and r['id'] == 1429 for r in server.find({'q': 'Elwynn'}))


def test_icon_export_reads_extracted_declaration():
    wanted = export_icons.wanted()
    assert len(wanted) == 19
    installed = json.loads((ROOT/'demo/icons/icons.json').read_text())['icons']
    assert all(k in installed for k in wanted)


def test_walk_and_pin_limits():
    with pytest.raises(ValueError):
        server.walk(dict(inst=0,c0=0,r0=0,c1=1024,r1=1024))
    with pytest.raises(ValueError):
        server.pins(dict(inst=0,zoom=0,c0=0,r0=0,c1=64,r1=64,layers='flight'))
