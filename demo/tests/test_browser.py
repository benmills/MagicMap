"""Browser integration checks. Run after `pip install playwright && playwright install chromium`.
Optional PLAYWRIGHT_CHROMIUM_EXECUTABLE selects an already installed browser.
All test terrain/scenery is served through request fixtures, never installed as game assets.
"""
import json
import os
from pathlib import Path
import struct
import sys
import threading
from http.server import ThreadingHTTPServer

import pytest

playwright = pytest.importorskip('playwright.sync_api')
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server


@pytest.fixture(scope='module')
def url():
    http = ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
    thread = threading.Thread(target=http.serve_forever, daemon=True)
    thread.start()
    yield f'http://127.0.0.1:{http.server_port}'
    http.shutdown()
    http.server_close()


@pytest.fixture(scope='module')
def browser():
    with playwright.sync_playwright() as p:
        b = p.chromium.launch(executable_path=os.getenv('PLAYWRIGHT_CHROMIUM_EXECUTABLE'),
                              args=['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'])
        yield b
        b.close()


@pytest.fixture
def page(browser):
    context = browser.new_context(viewport={'width': 1200, 'height': 850})
    p = context.new_page()
    errors = []
    p.on('pageerror', lambda error: errors.append(str(error)))
    # Fonts are cosmetic and must never gate the app or tests.
    p.route('https://fonts.googleapis.com/**', lambda r: r.abort())
    p.route('https://fonts.gstatic.com/**', lambda r: r.abort())
    yield p
    context.close()
    assert not errors, errors


def ready(page, url, hash=''):
    page.goto(url+hash)
    page.wait_for_function('state.camera && assets && !restoring && tiles.length>0')


def fixture_assets(page, missing=False, scenery=False, inst=0, imagery=False, preview=False, native_offset=0):
    rows = []
    blobs = {}
    preview_points, preview_faces, preview_ranges = [], [], []
    c0, r0 = (30, 33) if inst == 1 else (29, 48)
    for c in range(c0, c0+5):
        for r in range(r0, r0+5):
            key = c*64+r
            vertices = [(c,r,50),(c+1,r,150),(c+1,r+1,150),(c,r+1,50)]
            data = struct.pack('<4sII', b'MMT1', 4, 6) + b''.join(struct.pack('<3f',*v) for v in vertices) + struct.pack('<6I',0,1,2,0,2,3)
            blobs[f'{key}.mmt'] = data
            if native_offset:
                blobs[f'{key}-native.mmt'] = struct.pack('<4sII',b'MMT1',4,6)+b''.join(struct.pack('<3f',x,y,h+native_offset) for x,y,h in vertices)+struct.pack('<6I',0,1,2,0,2,3)
            preview_ranges.append(dict(key=key,offset=len(preview_faces),count=6))
            preview_faces.extend(len(preview_points)+i for i in (0,1,2,0,2,3))
            preview_points.extend(vertices)
            rows.append(dict(key=key,min=50,max=150,lods=dict(coarse=f'{key}.mmt',detail=f'{key}.mmt',native=f'{key}-native.mmt' if native_offset else f'{key}.mmt')))
    def assets(route):
        result = route.fetch().json()
        result['terrain'] = dict(available=not missing,reason='Test ground is unavailable' if missing else 'Test terrain',data=dict(
            format='magicmap-terrain-v1',product='wow_classic_beta',version='1.60.1.70450',inst=inst,tiles=rows))
        if preview:
            result['terrain']['data']['preview'] = dict(mesh='preview.mmt',image='preview.webp',bounds=[c0,r0,c0+5,r0+5],tiles=preview_ranges)
        # No map imagery needed to exercise actual WebGL drawing and ground picking.
        result['tiles'] = [t['key'] for t in rows] if imagery else []
        result['objects'] = dict(available=scenery,reason='Test scenery',data=dict(tiles=[dict(key=30*64+50,file='scene.json')]))
        route.fulfill(json=result)
    page.route(f'**/api/assets?inst={inst}',assets)
    if preview:
        blobs['preview.mmt'] = struct.pack('<4sII',b'MMT1',len(preview_points),len(preview_faces)) + b''.join(struct.pack('<3f',*v) for v in preview_points) + struct.pack(f'<{len(preview_faces)}I',*preview_faces)
    page.route(f'**/terrain/{inst}/*.mmt*',lambda r:r.fulfill(body=blobs[r.request.url.rsplit('/',1)[1].split('?')[0]],content_type='application/octet-stream'))
    if imagery or preview:
        # A real decodable image, with all size variants available for upgrade tests.
        from PIL import Image
        import io
        pictures = {}
        for size in (64,128,256,512):
            out = io.BytesIO()
            Image.new('RGB',(size,size),(60,120,80)).save(out,format='WEBP')
            pictures[size] = out.getvalue()
        def tile(route):
            path = route.request.url.split('?')[0].split('/')
            size = int(path[-2]) if path[-3] == str(inst) else 512
            route.fulfill(body=pictures[size],content_type='image/webp')
        page.route(f'**/tiles/{inst}/**',tile)
        if preview:
            page.route(f'**/terrain/{inst}/preview.webp*',lambda r:r.fulfill(body=pictures[64],content_type='image/webp'))
    if scenery:
        scene = dict(meshes=[dict(id='roof',positions=[-20,-20,0,20,-20,0,20,20,0,-20,20,0],indices=[0,1,2,0,2,3])],
                     instances=[dict(id='fixture-building',name='Fixture building',mesh='roof',col=30.9,row=50.9,height=190,heading=0,scale=1)])
        page.route('**/objects/0/scene.json*',lambda r:r.fulfill(json=scene))


def test_npc_quest_item_source_flow(page,url):
    if server.Atlas.Data.Npcs is None:
        pytest.skip('Questie-derived data is not installed')
    ready(page,url,'#view=2d')
    assert page.evaluate('state.mode') == '2d'
    page.locator('#q').fill('Eagan Peltskinner')
    page.locator('#results button').first.click()
    page.locator('#card button').filter(has_text='Wolves Across the Border').first.click()
    page.locator('#card button').filter(has_text='Tough Wolf Meat').click()
    playwright.expect(page.locator('#card h2')).to_have_text('Tough Wolf Meat')
    page.locator('#card button').filter(has_text='◎ Young Wolf').click()
    page.wait_for_function('highlight?.pts.length>0 && highlight.pts.every(p=>p.kind==="npc" && p.id===299)')
    assert page.evaluate('highlight.pts.every(p=>p.kind==="npc" && p.id===299)')
    page.locator('#card [aria-label="Young Wolf details"]').click()
    playwright.expect(page.locator('#card h2')).to_have_text('Young Wolf')
    page.locator('#card [aria-label="Back"]').click()
    playwright.expect(page.locator('#card h2')).to_have_text('Tough Wolf Meat')


def test_map_search_cross_map_entity_and_fit_without_uimap(page,url):
    ready(page,url)
    page.locator('#q').fill('Kalimdor')
    page.locator('#results button').first.click()
    page.wait_for_function('state.inst===1 && !restoring && assets')
    page.locator('#q').fill('Hogger')
    page.locator('#results button').first.click()
    page.wait_for_function('state.inst===0 && highlight?.pts.length===1')
    page.select_option('#mapSelect','37')
    page.wait_for_function('state.inst===37 && assets && tiles.length>0')
    page.locator('#fit').click()
    page.wait_for_function('!motion')
    assert page.evaluate('Number.isFinite(state.camera.zoom)')


def test_missing_assets_webgl_unavailable_and_icon_fallback(page,url):
    fixture_assets(page,missing=True)
    page.route('**/icons/**',lambda r:r.fulfill(status=404,body='missing'))
    ready(page,url,'#map=0')
    page.locator('#view3d').click()
    page.wait_for_function('$("status").textContent.includes("Using 2D")')
    assert page.evaluate('state.mode') == '2d'
    assert page.locator('#mapSelect option').count() >= 43
    page.unroute('**/api/assets?inst=0')
    fixture_assets(page)
    page.add_init_script("const original=HTMLCanvasElement.prototype.getContext;HTMLCanvasElement.prototype.getContext=function(type,...args){return type==='webgl2'?null:original.call(this,type,...args)}")
    page.reload()
    page.wait_for_function('assets && !restoring')
    page.locator('#view3d').click()
    page.wait_for_function('$("status").textContent.includes("WebGL2")')
    assert page.evaluate('state.mode') == '2d'


def test_3d_projected_highlights_picking_layers_and_shared_url(page,url):
    fixture_assets(page)
    ready(page,url,'#map=0&x=30.749&y=50.919&z=620&view=3d&tilt=48&yaw=0.4&select=npc:448&sources=npc:448&layers=flight,labels')
    page.wait_for_function('state.mode==="3d" && terrain.sample(30.749,50.919)?.resolution==="native"')
    before=page.evaluate('({...state.camera})')
    assert page.evaluate('terrain.gl.getError()') == 0
    playwright.expect(page.locator('#card h2')).to_have_text('Hogger')
    page.locator('#card [aria-label="Close"]').click()
    pos=page.evaluate('toScreen(30.749,50.919)')
    picked=page.evaluate('terrain.pick(...toScreen(30.749,50.919))')
    assert picked == pytest.approx([30.749,50.919],abs=1e-4)
    page.mouse.click(*pos)
    page.wait_for_function('state.selection?.id===448')
    page.locator('#view2d').click()
    page.wait_for_function('state.mode==="2d"')
    assert page.evaluate('state.camera') == before
    page.locator('#view3d').click()
    page.wait_for_function('state.mode==="3d"')
    page.locator('#tilt').fill('60')
    page.locator('#share').click()
    shared=page.url
    page.reload()
    page.wait_for_function('state.mode==="3d" && !restoring && highlight?.pts.length===1')
    assert page.evaluate('state.tilt') == 60
    assert page.evaluate('[...layerOn].sort()') == ['flight','labels']
    assert page.evaluate('state.camera') == before
    playwright.expect(page.locator('#card h2')).to_have_text('Hogger')


def test_stale_pin_and_walk_responses_cannot_cross_maps(page,url):
    ready(page,url,'#map=0&view=2d&layers=flight')
    held=[]
    page.route('**/api/pins?inst=0&**',lambda route:held.append(route))
    page.route('**/api/walk?inst=0&**',lambda route:held.append(route))
    page.evaluate('state.camera.zoom=160;walkOn=true;settled()')
    page.wait_for_timeout(450)
    assert held
    page.select_option('#mapSelect','1')
    page.wait_for_function('state.inst===1 && assets && tiles.length>0')
    for route in held:
        result=[] if '/pins?' in route.request.url else dict(c0=9001,r0=9001,rows=['f'])
        if isinstance(result,list):result=[dict(layer='flight',kind='flight',id=999999,col=32,row=32)]
        route.fulfill(json=result)
    page.wait_for_timeout(500)
    assert page.evaluate('!pins.some(p=>p.id===999999) && walk?.c0!==9001')


def test_phone_bottom_sheet_and_touch_controls(browser,url):
    context=browser.new_context(viewport={'width':390,'height':844},device_scale_factor=2,is_mobile=True,has_touch=True)
    p=context.new_page()
    ready(p,url,'#map=0&select=quest:33')
    rect=p.locator('#card').bounding_box()
    assert rect['y']>300 and rect['y']+rect['height']==pytest.approx(844,abs=2)
    p.locator('#card [aria-label="Close"]').tap()
    p.locator('#zoomIn').tap()
    p.wait_for_function('!motion')
    assert p.evaluate('document.documentElement.scrollWidth<=innerWidth')
    context.close()


def test_scenery_selection_hook_and_ground_only_inspection(page,url):
    fixture_assets(page,scenery=True)
    page.add_init_script("window.addEventListener('atlas:building-select',e=>window.selectedBuilding=e.detail)")
    ready(page,url,'#map=0&x=30.9&y=50.9&z=700&view=3d&tilt=45&layers=scenery')
    page.wait_for_function('terrain?.objects.tiles.size===1 && terrain.sample(30.9,50.9)?.resolution==="native"')
    ground=page.evaluate('terrain.sample(30.9,50.9)')
    pos=page.evaluate('terrain.point(30.9,50.9,190)')
    page.mouse.click(pos[0],pos[1])
    page.wait_for_function('window.selectedBuilding?.buildingId==="fixture-building"')
    assert page.evaluate('selectedBuilding.roomId') is None
    assert page.evaluate('terrain.sample(30.9,50.9)') == ground
    page.evaluate("terrain.gl.getExtension('WEBGL_lose_context').loseContext()")
    page.wait_for_function('state.mode==="2d"')
    assert 'context lost' in page.locator('#status').inner_text()


def test_closing_card_invalidates_delayed_entity_response(page,url):
    ready(page,url,'#map=0&select=npc:448')
    held=[]
    page.route('**/api/npc?id=299',lambda route:held.append(route))
    page.evaluate('void run(()=>openCard("npc",299,{highlight:true}))()')
    page.wait_for_timeout(150)
    assert held
    page.locator('#card [aria-label="Close"]').click()
    held[0].fulfill(json=server.npc({'id':'299'}))
    page.wait_for_timeout(150)
    assert page.locator('#card').is_hidden()
    assert page.evaluate('state.selection') is None


@pytest.mark.parametrize('mode', ['2d', '3d'])
def test_drag_moves_the_map_with_the_pointer(page, url, mode):
    fixture_assets(page)
    ready(page,url,f'#map=0&x=31&y=50&z=300&view={mode}&yaw=0.8&tilt=55&layers=labels')
    if mode == '3d':
        page.wait_for_function('terrain.sample(31,50)')
    anchor = page.evaluate('activeView().plane ? activeView().plane(650,430) : toTile(650,430)')
    height = page.evaluate('terrain?.focus || 0')
    page.mouse.move(650,430)
    page.mouse.down()
    page.mouse.move(740,490,steps=8)
    # Check while held, before any 2D momentum is applied.
    page.wait_for_function('!pending')
    screen = page.evaluate('([c,r,h])=>state.mode==="3d" ? terrain.point(c,r,h).slice(0,2) : toScreen(c,r)', [*anchor,height])
    assert screen == pytest.approx([740,490],abs=1)
    page.mouse.up()
    page.wait_for_function('!motion')
    assert page.evaluate('Number.isFinite(state.camera.zoom)')


def test_orbit_and_cancelled_gesture(page,url):
    fixture_assets(page)
    ready(page,url,'#map=0&x=31&y=50&z=300&view=3d&tilt=40')
    before = page.evaluate('({...state.camera})')
    page.mouse.move(650,430)
    page.mouse.down(button='right')
    page.mouse.move(730,470,steps=8)
    page.mouse.up(button='right')
    assert page.evaluate('state.camera') == before
    assert page.evaluate('state.yaw') == pytest.approx(0.4)
    assert page.evaluate('state.tilt') == pytest.approx(46)
    assert page.evaluate('state.selection') is None
    page.keyboard.down('Shift')
    page.mouse.down()
    page.mouse.move(670,450,steps=6)
    page.mouse.up()
    page.keyboard.up('Shift')
    assert page.evaluate('state.yaw') == pytest.approx(0.1)
    assert page.evaluate('state.camera') == before
    # Lost capture must stop dragging even without a pointerup on the map.
    page.mouse.down()
    page.mouse.move(671,450)
    held = page.evaluate('({...state.camera})')
    page.evaluate('canvas.releasePointerCapture([...pts.keys()][0])')
    page.mouse.move(800,500)
    page.mouse.up()
    page.wait_for_function('pts.size===0')
    assert page.evaluate('state.camera') == held


@pytest.mark.parametrize('tilt,yaw', [(0,0), (45,0.8), (65,-1.7)])
def test_sloping_ground_stays_under_pointer_through_drag_and_release(page,url,tilt,yaw):
    fixture_assets(page)
    ready(page,url,f'#map=0&x=31.5&y=50.5&z=600&view=3d&tilt={tilt}&yaw={yaw}')
    page.wait_for_function('terrain.sample(31.5,50.5)?.resolution==="native" && terrain.pick(650,430)')
    anchor = page.evaluate('(()=>{const p=terrain.pick(650,430);return [...p,terrain.sample(...p).height]})()')
    page.mouse.move(650,430)
    page.mouse.down()
    for point in [(690,455),(730,490)]:
        page.mouse.move(*point,steps=4)
        page.wait_for_function('!pending')
        assert page.evaluate('p=>terrain.point(...p).slice(0,2)',anchor) == pytest.approx(point,abs=.1)
    page.wait_for_timeout(120)  # A held release stops; a flick is tested separately.
    page.mouse.up()
    page.wait_for_function('!pending && !gestureFrame')
    assert page.evaluate('p=>terrain.point(...p).slice(0,2)',anchor) == pytest.approx([730,490],abs=.1)
    assert page.evaluate('terrain.focusLocked') is False
    assert page.evaluate('toScreen(state.camera.cx,state.camera.cy)') == pytest.approx([600,425],abs=.1)


def test_navigation_retargets_ground_height_in_the_same_map(page,url):
    fixture_assets(page)
    ready(page,url,'#map=0&x=31.1&y=50.5&z=600&view=3d&tilt=65&yaw=0.8')
    page.wait_for_function('terrain.sample(31.1,50.5)?.resolution==="native"')
    assert page.evaluate('terrain.focus') == pytest.approx(60)
    page.evaluate('flyTo({cx:31.8,cy:50.5,zoom:600},50)')
    page.wait_for_function('!motion && !pending')
    assert page.evaluate('terrain.focus') == pytest.approx(130)
    assert page.evaluate('toScreen(31.8,50.5)') == pytest.approx([600,425],abs=.1)


def test_touch_drag_pinch_and_cancellation(page,url):
    fixture_assets(page)
    ready(page,url,'#map=0&x=31.5&y=50.5&z=600&view=3d&yaw=0.8&tilt=55')
    page.wait_for_function('terrain.sample(31.5,50.5)?.resolution==="native"')
    session = page.context.new_cdp_session(page)
    def touch(kind, points):
        session.send('Input.dispatchTouchEvent', {'type':kind, 'touchPoints':[
            dict(x=x,y=y,id=i) for i,(x,y) in enumerate(points)]})
    anchor = page.evaluate('terrain.plane(650,430)')
    height = page.evaluate('terrain.focus')
    touch('touchStart',[(650,430)])
    touch('touchMove',[(700,470)])
    page.wait_for_timeout(120)
    touch('touchEnd',[])
    page.wait_for_function('!pending')
    screen = page.evaluate('p=>terrain.point(...p).slice(0,2)', [*anchor,height])
    assert screen == pytest.approx([700,470],abs=1)
    zoom = page.evaluate('state.camera.zoom')
    pinch_anchor = page.evaluate('(()=>{const p=terrain.pick(650,430);return [...p,terrain.sample(...p).height]})()')
    touch('touchStart',[(600,430),(700,430)])
    touch('touchMove',[(590,450),(750,450)])
    touch('touchCancel',[])
    page.wait_for_function('pts.size===0 && !pending')
    assert page.evaluate('state.camera.zoom') == pytest.approx(zoom*1.6,rel=.01)
    assert page.evaluate('p=>terrain.point(...p).slice(0,2)',pinch_anchor) == pytest.approx([670,450],abs=.1)
    assert page.evaluate('state.selection') is None
    session.detach()


def test_default_flyover_pause_resume_and_shared_state(page,url):
    fixture_assets(page,inst=1)
    ready(page,url)
    page.wait_for_function('state.flyover && state.mode==="3d"')
    assert page.evaluate('state.inst') == 1
    assert page.evaluate('[...layerOn]') == ['labels']
    assert page.evaluate('[...state.labelTiers]') == ['zone']
    before = page.evaluate('({...state.camera})')
    before_tilt = page.evaluate('state.tilt')
    page.wait_for_function('p=>Math.abs(state.camera.cy-p.cy)>0.005',arg=before)
    assert page.evaluate('state.tilt') > before_tilt
    page.mouse.move(650,430)
    page.mouse.down()
    assert page.evaluate('state.flyover') is False
    page.mouse.move(700,460,steps=5)
    page.mouse.up()
    page.wait_for_function('!motion')
    paused = page.evaluate('({...state.camera})')
    page.wait_for_timeout(200)
    assert page.evaluate('state.camera') == paused
    page.locator('#flyover').click()
    page.wait_for_function('state.flyover')
    page.locator('#share').click()
    shared = page.url
    assert 'fly=1' in shared and 'names=zone' in shared
    page.reload()
    page.wait_for_function('state.flyover && !restoring')
    page.locator('#flyover').click()
    assert page.evaluate('state.flyover') is False
    page.wait_for_timeout(250)
    page.reload()
    page.wait_for_function('!restoring && assets')
    assert page.evaluate('state.flyover') is False
    page.locator('#flyover').click()
    page.locator('#q').fill('Hogger')
    assert page.evaluate('state.flyover') is False
    page.locator('#flyover').click()
    page.select_option('#mapSelect','0')
    page.wait_for_function('state.inst===0 && assets && !restoring')
    assert page.evaluate('state.flyover') is False
    page.locator('#view2d').click()
    page.wait_for_function('state.mode==="2d"')
    playwright.expect(page.locator('#flyover')).to_be_disabled()


def test_reduced_motion_does_not_autoplay_but_allows_manual_flyover(page,url):
    fixture_assets(page,inst=1)
    page.emulate_media(reduced_motion='reduce')
    ready(page,url)
    assert page.evaluate('state.mode') == '3d'
    assert page.evaluate('state.flyover') is False
    page.locator('#flyover').click()
    assert page.evaluate('state.flyover') is True
    page.evaluate("terrain.gl.getExtension('WEBGL_lose_context').loseContext()")
    page.wait_for_function('state.mode==="2d" && !state.flyover')


@pytest.mark.parametrize('mode', ['2d','3d'])
def test_label_sublayers_filter_rendering_and_restore_in_links(page,url,mode):
    fixture_assets(page)
    names = [dict(text='Major zone',col=31,row=50,tier='zone',rank=1,size=4),
             dict(text='Small subzone',col=31.8,row=50.4,tier='subzone',rank=2,size=1),
             dict(text='Town',col=30.3,row=50,tier='town',rank=3)]
    page.route('**/api/labels?inst=0',lambda r:r.fulfill(json=dict(labels=names)))
    ready(page,url,f'#map=0&x=31&y=50&z=240&view={mode}&tilt=40&layers=labels')
    page.wait_for_function('labelState.get(1)?.on')
    assert page.evaluate('labels.filter(l=>labelState.get(l.rank)?.on).map(l=>l.tier)') == ['zone']
    page.locator('#layersBtn').click()
    major = page.locator('[data-label-tier="zone"]')
    subzone = page.locator('[data-label-tier="subzone"]')
    playwright.expect(major).to_be_checked()
    playwright.expect(subzone).not_to_be_checked()
    subzone.check()
    page.wait_for_function('labelState.get(2)?.on')
    major.uncheck()
    page.wait_for_function('!labelState.has(1)')
    assert page.evaluate('labels.filter(l=>labelState.get(l.rank)?.on).map(l=>l.tier)') == ['subzone']
    page.locator('#share').click()
    shared = page.url
    assert 'names=subzone' in shared
    page.reload()
    page.wait_for_function('!restoring && labelState.get(2)?.on')
    assert page.evaluate('[...state.labelTiers]') == ['subzone']
    page.locator('#layersBtn').click()
    page.locator('[data-layer="labels"]').uncheck()
    playwright.expect(page.locator('[data-label-tier="subzone"]')).to_be_disabled()
    assert page.evaluate('layerOn.has("labels")') is False


def test_retina_textures_upgrade_without_untextured_mesh_changes(browser,url):
    context = browser.new_context(viewport={'width':390,'height':844},device_scale_factor=3,is_mobile=True,has_touch=True)
    page = context.new_page()
    errors = []
    page.on('pageerror',lambda e:errors.append(str(e)))
    fixture_assets(page,imagery=True)
    held = []
    page.route('**/tiles/0/256/**',lambda r:held.append(r))
    full_size = []
    page.route('**/tiles/0/*.webp*',lambda r:full_size.append(r))
    ready(page,url,'#map=0&x=31.2&y=50.2&z=60&view=3d&tilt=50&fly=0&layers=')
    page.wait_for_function('terrain.textures.cache.get(2034)?.size===128')
    assert page.locator('#terrain').evaluate('c=>[c.width,c.height]') == [1170,2532]
    assert page.evaluate('terrain.textureSize()') == 256
    assert page.evaluate('terrain.lod()') == 'coarse'
    page.wait_for_function('terrain.textures.waiting.get(2034)===256')
    page.evaluate('window.originalTexture=terrain.textures.cache.get(2034).texture;state.camera.zoom=600;draw()')
    page.wait_for_function('terrain.entry(2034)?.lod==="native"')
    assert page.evaluate('terrain.textures.get(2034).texture===originalTexture')
    # The obsolete 256 request must not block the now-visible 512 request.
    page.wait_for_function('terrain.textures.waiting.get(2034)===512')
    page.unroute('**/tiles/0/*.webp*')
    for route in full_size:
        route.fallback()
    page.wait_for_function('terrain.textures.cache.get(2034)?.size===512')
    page.unroute('**/tiles/0/256/**')
    for route in held:
        route.fallback()
    assert page.evaluate('terrain.gl.getError()') == 0
    assert page.evaluate('terrain.textures.cache.get(2034).texture!==originalTexture')
    assert not errors, errors
    context.close()


def test_delayed_textures_do_not_leak_across_maps(page,url):
    fixture_assets(page,imagery=True)
    fixture_assets(page,inst=1,imagery=True)
    held = []
    page.route('**/tiles/0/**',lambda r:held.append(r))
    ready(page,url,'#map=0&x=31&y=50&z=180&view=3d&fly=0')
    page.wait_for_function('terrain.textures.waiting.size>0')
    page.select_option('#mapSelect','1')
    page.wait_for_function('terrain.inst===1 && assets && terrain.textures.cache.size>0')
    for route in held:
        route.fallback()
    page.wait_for_timeout(150)
    assert page.evaluate('terrain.textures.inst') == 1
    assert page.evaluate('[...terrain.textures.cache.keys()].every(k=>k%64>=33 && k%64<38)')


def test_terrain_starts_before_delayed_icons_and_labels(page,url):
    fixture_assets(page,inst=1)
    held=[]
    page.route('**/icons/**',lambda r:held.append(r))
    page.route('**/api/labels?inst=1',lambda r:held.append(r))
    page.goto(url,wait_until='domcontentloaded')
    page.wait_for_function('state.mode==="3d" && terrain.cache.size>0')
    assert page.evaluate('restoring') is True
    assert page.locator('#flyover').is_enabled()
    for route in held:
        route.fallback()
    page.wait_for_function('!restoring && state.flyover')


def test_whole_map_preview_fills_delayed_ground_without_claiming_inspection(page,url):
    fixture_assets(page,preview=True,imagery=True)
    held = []
    def delay_tile(route):
        if '/preview.mmt' in route.request.url:
            route.fallback()
        else:
            held.append(route)
    page.route('**/terrain/0/*.mmt*',delay_tile)
    page.route('**/tiles/0/**',lambda r:r.abort())
    ready(page,url,'#map=0&view=3d&x=31.5&y=50.5&z=180&tilt=45&fly=0')
    page.wait_for_function('terrain.preview.gpu && terrain.preview.texture && !pending')
    assert page.evaluate('terrain.diagnostics().previewTiles') > 0
    assert page.evaluate('terrain.sample(31.5,50.5)') is None
    assert page.evaluate('terrain.pick(W/2,H/2)') is None
    pixel = page.evaluate('''(()=>{terrain.render();const gl=terrain.gl,p=new Uint8Array(4);
        gl.readPixels(gl.drawingBufferWidth/2,gl.drawingBufferHeight/2,1,1,gl.RGBA,gl.UNSIGNED_BYTE,p);return [...p]})()''')
    assert pixel[1] > 60 and pixel[1] > pixel[0]
    page.unroute('**/terrain/0/*.mmt*',delay_tile)
    for route in held:
        route.fallback()
    page.wait_for_function('terrain.visible.every(t=>terrain.entry(t.key)) && !pending')
    assert page.evaluate('terrain.diagnostics().previewTiles') == 0
    assert page.evaluate('terrain.sample(31.5,50.5).groundOnly') is True
    assert page.evaluate('terrain.gl.getError()') == 0


def test_preview_failure_and_stale_map_load_leave_normal_terrain_usable(page,url):
    fixture_assets(page,preview=True)
    fixture_assets(page,inst=1)
    held = []
    page.route('**/terrain/0/preview.mmt*',lambda r:held.append(r))
    ready(page,url,'#map=0&view=3d&x=31.5&y=50.5&z=180&fly=0')
    page.wait_for_function('terrain.preview.pending && terrain.sample(31.5,50.5)')
    page.select_option('#mapSelect','1')
    page.wait_for_function('terrain.inst===1 && assets && terrain.cache.size>0')
    for route in held:
        route.fallback()
    page.wait_for_timeout(100)
    assert page.evaluate('terrain.preview.gpu') is None
    assert page.evaluate('terrain.preview.ranges.size') == 0
    page.unroute('**/terrain/0/preview.mmt*')
    page.route('**/terrain/0/preview.mmt*',lambda r:r.fulfill(status=404,body='missing'))
    page.select_option('#mapSelect','0')
    page.wait_for_function('terrain.inst===0 && terrain.preview.failed && terrain.cache.size>0')
    assert page.evaluate('state.mode') == '3d'
    assert page.evaluate('terrain.gl.getError()') == 0


@pytest.mark.parametrize('mode',['2d','3d'])
def test_flick_coasts_and_new_touch_stops_it_immediately(page,url,mode):
    fixture_assets(page)
    ready(page,url,f'#map=0&view={mode}&x=31.5&y=50.5&z=300&tilt=55&fly=0')
    if mode=='3d':
        page.wait_for_function('terrain.sample(31.5,50.5)')
    page.mouse.move(630,430)
    page.mouse.down()
    for x in [650,670,690,710]:
        page.mouse.move(x,430)
        page.wait_for_timeout(20)
    page.mouse.up()
    page.wait_for_function('motionKind==="glide"')
    before=page.evaluate('({...state.camera})')
    page.wait_for_function('p=>state.camera.cx!==p.cx || state.camera.cy!==p.cy',arg=before)
    page.mouse.down()
    assert page.evaluate('motion') is None
    stopped=page.evaluate('({...state.camera})')
    page.wait_for_timeout(150)
    assert page.evaluate('state.camera') == stopped
    page.mouse.up()


def test_two_finger_rotation_and_parallel_tilt_keep_the_gesture_anchor(page,url):
    fixture_assets(page)
    ready(page,url,'#map=0&view=3d&x=31.5&y=50.5&z=600&tilt=40&fly=0')
    page.wait_for_function('terrain.sample(31.5,50.5)?.resolution==="native"')
    session=page.context.new_cdp_session(page)
    def touch(kind,points):
        session.send('Input.dispatchTouchEvent',{'type':kind,'touchPoints':[dict(x=x,y=y,id=i) for i,(x,y) in enumerate(points)]})
    anchor=page.evaluate('(()=>{const p=terrain.pick(650,450);return [...p,terrain.sample(...p).height]})()')
    touch('touchStart',[(600,450),(700,450)])
    touch('touchMove',[(620,410),(680,490)])
    page.wait_for_function('!gestureFrame && !pending')
    assert page.evaluate('state.yaw') == pytest.approx(.927295218,abs=.001)
    assert page.evaluate('state.camera.zoom') == pytest.approx(600)
    assert page.evaluate('p=>terrain.point(...p).slice(0,2)',anchor) == pytest.approx([650,450],abs=.1)
    touch('touchCancel',[])
    page.wait_for_function('pts.size===0')
    anchor=page.evaluate('(()=>{const p=terrain.pick(650,400);return [...p,terrain.sample(...p).height]})()')
    touch('touchStart',[(600,400),(700,400)])
    touch('touchMove',[(600,450),(700,450)])
    page.wait_for_function('!gestureFrame && !pending')
    assert page.evaluate('state.tilt') == pytest.approx(50)
    assert page.evaluate('state.camera.zoom') == pytest.approx(600)
    assert page.evaluate('p=>terrain.point(...p).slice(0,2)',anchor) == pytest.approx([650,400],abs=.1)
    touch('touchCancel',[])
    assert page.evaluate('state.selection') is None
    session.detach()


def test_trackpad_pans_and_control_pinch_zooms(page,url):
    fixture_assets(page)
    ready(page,url,'#map=0&view=3d&x=31.5&y=50.5&z=300&tilt=50&fly=0')
    page.wait_for_function('terrain.sample(31.5,50.5)')
    page.mouse.move(650,430)
    before=page.evaluate('({...state.camera})')
    page.mouse.wheel(20,15)
    page.wait_for_function('wheelTimer===null && !pending')
    assert page.evaluate('state.camera.zoom') == before['zoom']
    assert page.evaluate('state.camera.cx') != before['cx']
    page.dispatch_event('#map','wheel',dict(deltaY=-20,deltaX=0,deltaMode=0,ctrlKey=True,clientX=650,clientY=430))
    page.wait_for_function('wheelTimer===null && !pending')
    assert page.evaluate('state.camera.zoom') > before['zoom']


def test_ground_refinement_does_not_reposition_a_stationary_camera(page,url):
    fixture_assets(page,native_offset=100)
    held=[]
    page.route('**/terrain/0/*-native.mmt*',lambda r:held.append(r))
    ready(page,url,'#map=0&view=3d&x=31.5&y=50.5&z=600&tilt=55&fly=0')
    page.wait_for_function('terrain.sample(31.5,50.5) && !terrain.focusPending')
    before=page.evaluate('({camera:{...state.camera},focus:terrain.focus})')
    assert page.evaluate('!!terrain.decoder.worker')
    page.unroute('**/terrain/0/*-native.mmt*')
    for route in held: route.fallback()
    page.wait_for_function('terrain.sample(31.5,50.5)?.resolution==="native" && !pending')
    assert page.evaluate('state.camera') == before['camera']
    assert page.evaluate('terrain.focus') == before['focus']
    assert page.evaluate('terrain.sample(31.5,50.5).height') == before['focus']+100
