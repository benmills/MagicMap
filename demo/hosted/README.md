# The map review on the hosted demo

The hosted demo (magic-map-outdoor.exe.xyz) is its own code on the VM, not this repo's demo/. The map
review (docs/hardening-plan.md M6) ships as three files from here plus a small patch to its pages.
`review.patch` was made against its files as served on 2026-10-27: server.py, index.html, core.js,
navigation.js, cards.js, app.js.

## Deploy (on the VM, in the hosted demo's folder: the one holding server.py and index.html)

1. Copy in, from this repo:
   - `demo/review.js` → `review.js`
   - `demo/review_api.py` → `review_api.py`
   - `demo/lint/issues.json` → `lint/issues.json`
2. `patch -p1 < review.patch` (`patch -p1 --dry-run` first: it fails cleanly if the pages have moved on).
3. Keep the marks outside the served folder, so they aren't a public file and a redeploy can't overwrite them:
   `export MAGICMAP_REVIEW=~/magic-map-review/decisions.json`
4. If the site is public (not behind exe.dev's sign-in), set a token. The page asks for it once per browser:
   `export MAGICMAP_REVIEW_TOKEN=<something>`
5. Restart the server.

To check it: `curl -s https://magic-map-outdoor.exe.xyz/api/lint | head -c 200` should name build 1.60.1.70532.
The page then has a **Review** button.

## Reading the marks back

    .venv/bin/python tools/review.py --from https://magic-map-outdoor.exe.xyz/
    .venv/bin/python tools/review.py --from https://magic-map-outdoor.exe.xyz/ --save docs/map-review.json

## After a linter change

Regenerate the issues, then copy `lint/issues.json` again. Issue ids are stable, so the marks carry over.
An id that's no longer in the file shows as GONE in tools/review.py.

    .venv/bin/python tools/maplint.py --wow "/Applications/World of Warcraft" -q --issues demo/lint/issues.json
