from main import app


def test_health():
    r = app.test_client().get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_ready():
    assert app.test_client().get("/ready").status_code == 200


def test_version():
    r = app.test_client().get("/version")
    assert r.status_code == 200
    assert "git_sha" in r.get_json()
