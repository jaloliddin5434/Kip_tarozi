from app.core.config import settings


def test_login_muvaffaqiyatli(client, admin):
    javob = client.post("/api/v1/auth/login", json={"login": "test_admin", "parol": "parol123"})
    assert javob.status_code == 200
    tanani = javob.json()
    assert "access_token" in tanani

    men = client.get("/api/v1/auth/men", headers={"Authorization": f"Bearer {tanani['access_token']}"})
    assert men.status_code == 200
    assert men.json()["login"] == "test_admin"


def test_login_notogri_parol(client, admin):
    javob = client.post("/api/v1/auth/login", json={"login": "test_admin", "parol": "notogri"})
    assert javob.status_code == 401


def test_login_bloklash(client, admin, monkeypatch):
    monkeypatch.setattr(settings, "LOGIN_MAX_ATTEMPTS", 3)

    for _ in range(3):
        javob = client.post("/api/v1/auth/login", json={"login": "test_admin", "parol": "xato"})
        assert javob.status_code == 401

    # 3-chi xatodan keyin bloklanadi — hatto to'g'ri parol bilan ham kirib bo'lmaydi
    javob = client.post("/api/v1/auth/login", json={"login": "test_admin", "parol": "parol123"})
    assert javob.status_code == 429
