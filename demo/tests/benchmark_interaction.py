"""Opt-in real-asset input/loading benchmark; reports main-thread tasks over 50 ms.

This uses headless Chromium, not physical iPhone GPU/input timing. Requires generated
Kalimdor assets. PLAYWRIGHT_CHROMIUM_EXECUTABLE can select an installed browser.
"""
import argparse,json,os
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--url',default='http://localhost:8124')
ap.add_argument('--label',default='current')
args=ap.parse_args()
with sync_playwright() as p:
 b=p.chromium.launch(executable_path=os.getenv('PLAYWRIGHT_CHROMIUM_EXECUTABLE'),args=['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'])
 page=b.new_page(viewport={'width':800,'height':600})
 page.route('https://fonts.googleapis.com/**',lambda r:r.abort())
 page.route('https://fonts.gstatic.com/**',lambda r:r.abort())
 page.add_init_script('window.longTasks=[];new PerformanceObserver(list=>longTasks.push(...list.getEntries().map(e=>({at:e.startTime,ms:e.duration})))).observe({type:"longtask",buffered:true})')
 page.goto(args.url.rstrip('/')+'/#map=1&view=3d&fly=0&x=32&y=35.5&z=600&tilt=50&layers=labels')
 page.wait_for_function('state.mode==="3d" && terrain.visible.length>0')
 start=page.evaluate('performance.now()')
 page.mouse.move(450,300);page.mouse.down()
 for i in range(30):
  page.mouse.move(450+i*5,300+i*2)
  page.wait_for_timeout(16)
 page.mouse.up()
 page.wait_for_timeout(3000)
 tasks=page.evaluate('start=>longTasks.filter(t=>t.at>=start)',start)
 print(json.dumps({'label':args.label,'long_tasks':len(tasks),'blocking_ms':sum(max(0,t['ms']-50) for t in tasks),'worst_ms':max([t['ms'] for t in tasks] or [0]),'diagnostics':page.evaluate('terrain.diagnostics()')}),flush=True)
 b.close()
