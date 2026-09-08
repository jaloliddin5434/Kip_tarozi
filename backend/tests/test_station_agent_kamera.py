"""Stansiya Agenti — /kamera/surat endpoint.

Handler'ni to'g'ridan-to'g'ri chaqiramiz (FastAPI lifespan / RS232 thread'larini
ko'tarmasdan). Kamera chaqiruvi mocklanadi — real tarmoqqa chiqmaydi.
"""

from app.services.rs232 import station_agent

JPEG = b"\xff\xd8\xff\xe0agent\xff\xd9"


def test_kamera_surat_jpeg_qaytaradi(monkeypatch):
    monkeypatch.setattr(station_agent, "kamera_snapshot_ol", lambda: JPEG)
    javob = station_agent.kamera_surat()
    assert javob.status_code == 200
    assert javob.media_type == "image/jpeg"
    assert javob.body == JPEG


def test_kamera_ulanmasa_204(monkeypatch):
    monkeypatch.setattr(station_agent, "kamera_snapshot_ol", lambda: None)
    assert station_agent.kamera_surat().status_code == 204


def test_kamera_bosh_javob_204(monkeypatch):
    monkeypatch.setattr(station_agent, "kamera_snapshot_ol", lambda: b"")
    assert station_agent.kamera_surat().status_code == 204
