"""Measure a cold Kalimdor view at 3x phone density and a fixed network budget.

PLAYWRIGHT_CHROMIUM_EXECUTABLE=/path/to/chrome python demo/tests/benchmark_loading.py \
    --url http://localhost:8124

Requires generated Kalimdor terrain/images and Playwright. This measures browser
emulation, not physical iPhone GPU performance. It is an opt-in benchmark, not a
timing assertion in the deterministic test suite.
"""
import argparse
import json
import os
import time

from playwright.sync_api import sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://localhost:8124')
    args = parser.parse_args()
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=os.getenv('PLAYWRIGHT_CHROMIUM_EXECUTABLE'),
            args=['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'])
        page = browser.new_page(viewport={'width':390,'height':844}, device_scale_factor=3,
                                is_mobile=True, has_touch=True)
        cdp = page.context.new_cdp_session(page)
        cdp.send('Network.enable')
        cdp.send('Network.emulateNetworkConditions', dict(offline=False, latency=60,
                 downloadThroughput=1_000_000, uploadThroughput=500_000))
        page.route('https://fonts.googleapis.com/**', lambda route: route.abort())
        page.route('https://fonts.gstatic.com/**', lambda route: route.abort())
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        start = time.monotonic()
        page.goto(args.url.rstrip('/')+'/#map=1&view=3d&x=32&y=35.5&z=180&tilt=48&layers=labels&names=zone&fly=0')
        page.wait_for_function('terrain?.preview.gpu && terrain.preview.texture',timeout=60000)
        preview_seconds = time.monotonic()-start
        page.wait_for_function('terrain?.visible.length>0 && terrain.visible.every(t=>terrain.entry(t.key))', timeout=60000)
        ground_seconds = time.monotonic()-start
        page.wait_for_function('terrain.visible.every(t=>!terrain.tileAssets.has(t.key) || terrain.textures.cache.get(t.key)?.size>=terrain.textureSize())', timeout=60000)
        result = dict(preview_seconds=round(preview_seconds,2), ground_seconds=round(ground_seconds,2), image_seconds=round(time.monotonic()-start,2),
            stats=page.evaluate('terrain.diagnostics()'),
            resources=page.evaluate('''performance.getEntriesByType("resource")
                .filter(r=>r.name.includes(".mmt")||r.name.includes(".webp"))
                .reduce((s,r)=>({count:s.count+1,encoded:s.encoded+r.encodedBodySize,
                    decoded:s.decoded+r.decodedBodySize}),{count:0,encoded:0,decoded:0})'''), errors=errors)
        print(json.dumps(result, indent=2))
        browser.close()
        if errors:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
