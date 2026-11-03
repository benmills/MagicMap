"""Compressed assets keep their public paths and exact decompressed contents."""
import gzip
from http.server import ThreadingHTTPServer
from pathlib import Path
import sys
import threading
from urllib.request import Request, urlopen

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server
from static_assets import accepts_gzip, compressed_file


@pytest.fixture
def assets_http(tmp_path, monkeypatch):
    monkeypatch.setattr(server, 'DEMO', str(tmp_path))
    folder = tmp_path/'terrain'/'1'
    folder.mkdir(parents=True)
    path = folder/'test.mmt'
    path.write_bytes(b'MMT1' + bytes(range(256))*200)
    compressed_file.cache_clear()
    http = ThreadingHTTPServer(('127.0.0.1',0), server.Handler)
    thread = threading.Thread(target=http.serve_forever,daemon=True)
    thread.start()
    yield path, f'http://127.0.0.1:{http.server_port}/terrain/1/test.mmt?v=test'
    http.shutdown()
    http.server_close()
    thread.join()


def test_compressed_terrain_and_head_are_standard_http(assets_http):
    path,url = assets_http
    with urlopen(Request(url,headers={'Accept-Encoding':'gzip'})) as response:
        body=response.read()
        assert response.headers['Content-Encoding'] == 'gzip'
        assert response.headers['Vary'] == 'Accept-Encoding'
        assert 'max-age=' in response.headers['Cache-Control']
        assert gzip.decompress(body) == path.read_bytes()
        assert len(body) < len(path.read_bytes())/4
    with urlopen(Request(url,headers={'Accept-Encoding':'gzip'},method='HEAD')) as response:
        assert response.read() == b''
        assert int(response.headers['Content-Length']) == len(body)
    assert compressed_file.cache_info().hits >= 1


def test_identity_and_updated_assets_are_not_stale(assets_http):
    path,url = assets_http
    for encoding in ('identity','gzip;q=0'):
        with urlopen(Request(url,headers={'Accept-Encoding':encoding})) as response:
            assert response.headers.get('Content-Encoding') is None
            assert response.read() == path.read_bytes()
    with urlopen(Request(url,headers={'Accept-Encoding':'gzip'})) as response:
        previous=response.read()
    path.write_bytes(b'MMT1' + b'updated terrain'*300)
    with urlopen(Request(url,headers={'Accept-Encoding':'gzip'})) as response:
        current=response.read()
        assert current != previous
        assert gzip.decompress(current) == path.read_bytes()


def test_gzip_negotiation():
    assert accepts_gzip('br, gzip, deflate')
    assert accepts_gzip('gzip; q=0.5')
    assert not accepts_gzip('gzip;q=0')
    assert not accepts_gzip('gzip;q=invalid')
    assert not accepts_gzip('br')
