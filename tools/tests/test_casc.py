"""The local CASC reader, on a synthetic install."""
import pytest

from fixtures import build_casc
from mmtools.casc import CascStore


@pytest.fixture(scope="module")
def store(tmp_path_factory):
    install = str(tmp_path_factory.mktemp("casc"))
    files = {i: bytes([i % 251]) * (100 + i) for i in range(1, 40)}
    files[123456789] = b"big id"
    build_casc(install, "wow_x", "1.2.3.4", files, page_entries=4)
    return CascStore(install, "wow_x"), files


def test_reads_every_file(store):
    casc, files = store
    casc.resolve(files)
    for fdid, data in files.items():
        assert casc.read(fdid) == data


def test_version_and_missing(store):
    casc, _ = store
    assert casc.version == "1.2.3.4"
    assert casc.read(999) is None and casc.ckey(999) is None


def test_unknown_product(tmp_path):
    build_casc(str(tmp_path), "wow_x", "1.0.0.1", {1: b"a"})
    with pytest.raises(SystemExit):
        CascStore(str(tmp_path), "wow_nope")
