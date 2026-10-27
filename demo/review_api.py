"""The map review's backend (docs/hardening-plan.md M6): the linter's issues and the review's decisions.

Shared by demo/server.py and the hosted demo's server: each routes three paths here.

  GET  /api/lint      the issues file, tools/maplint.py --issues (default demo/lint/issues.json, or $MAGICMAP_LINT)
  GET  /api/review    the decisions: { schema, updated, decisions: { "<issue id>": decision }, log: [decision...] }
  POST /api/review    { id, status, note, by } -> the decisions as GET. status: accepted, rejected, later or null
                      (back to open). With $MAGICMAP_REVIEW_TOKEN set, the X-Review-Token header must match.

A decision is { id, status, note, by, at } (at: ISO time, UTC). The log keeps every change, oldest first, so a
mark changed by mistake can be found again. The file is $MAGICMAP_REVIEW (default demo/review/decisions.json),
written whole and swapped in (os.replace), under one lock: two reviewers' saves don't interleave.

tools/review.py reads it back (from a URL or the file) beside the issues.
"""
from __future__ import annotations

import datetime
import hmac
import json
import os
import threading

DEMO = os.path.dirname(os.path.abspath(__file__))
LINT = os.environ.get("MAGICMAP_LINT") or os.path.join(DEMO, "lint", "issues.json")
STORE = os.environ.get("MAGICMAP_REVIEW") or os.path.join(DEMO, "review", "decisions.json")
TOKEN = os.environ.get("MAGICMAP_REVIEW_TOKEN") or ""
STATUSES = ("accepted", "rejected", "later")
MAX_BODY, MAX_NOTE, MAX_ID, MAX_BY = 16384, 4000, 200, 60

lock = threading.Lock()


class Refused(Exception):
    """A request the review turns down: its HTTP status and why."""

    def __init__(self, status: int, why: str):
        super().__init__(why)
        self.status = status


def lint() -> bytes:
    try:
        with open(LINT, "rb") as f:
            return f.read()
    except FileNotFoundError:
        return json.dumps({"schema": 1, "issues": [], "missing": os.path.basename(LINT)}).encode()


def read() -> dict:
    try:
        with open(STORE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"schema": 1, "updated": None, "decisions": {}, "log": []}


def review() -> bytes:
    with lock:
        return json.dumps(read()).encode()


def decide(body: bytes, headers) -> bytes:
    if TOKEN and not hmac.compare_digest(headers.get("X-Review-Token", ""), TOKEN):
        raise Refused(401, "review token needed")
    if len(body) > MAX_BODY:
        raise Refused(413, "too long")
    try:
        d = json.loads(body)
    except ValueError:
        raise Refused(400, "not JSON") from None
    id, status, note, by = d.get("id"), d.get("status"), d.get("note") or "", d.get("by") or ""
    if not isinstance(id, str) or not 0 < len(id) <= MAX_ID:
        raise Refused(400, "id")
    if status is not None and status not in STATUSES:
        raise Refused(400, "status")
    if not isinstance(note, str) or len(note) > MAX_NOTE or not isinstance(by, str) or len(by) > MAX_BY:
        raise Refused(400, "note or by")
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    mark = {"id": id, "status": status, "note": note.strip(), "by": by.strip(), "at": now}
    with lock:
        doc = read()
        if status is None and not mark["note"]:
            doc["decisions"].pop(id, None)
        else:
            doc["decisions"][id] = mark
        doc["log"].append(mark)
        doc["updated"] = now
        os.makedirs(os.path.dirname(STORE), exist_ok=True)
        tmp = STORE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(doc, f, indent=1)
        os.replace(tmp, STORE)
        return json.dumps(doc).encode()


def handle(method: str, path: str, body: bytes, headers) -> tuple[int, bytes] | None:
    """The response for one of the review's paths, or None for any other path."""
    try:
        if path == "/api/lint" and method == "GET":
            return 200, lint()
        if path == "/api/review" and method == "GET":
            return 200, review()
        if path == "/api/review" and method == "POST":
            return 200, decide(body, headers)
    except Refused as e:
        return e.status, json.dumps({"error": str(e)}).encode()
    return None
