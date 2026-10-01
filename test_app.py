import os

import pytest

from app import app, get_db, init_db

ADMIN_PASSWORD = os.environ["TASKFLOW_ADMIN_PASSWORD"]
SQLI_LOGIN_PAYLOAD = "' OR '1'='1' --"
XSS_PAYLOAD = "<script>alert('xss')</script>"


@pytest.fixture
def client(tmp_path):
    app.config.update(TESTING=True, DATABASE=str(tmp_path / "taskflow-test.db"))
    with app.app_context():
        init_db()
    with app.test_client() as test_client:
        yield test_client


def login(client, username, password):
    return client.post("/login", data={"username": username, "password": password})


def create_task(client, title, description=""):
    return client.post("/tasks/new", data={"title": title, "description": description})


def test_login_com_credenciais_validas_redireciona_para_tarefas(client):
    response = login(client, "admin", ADMIN_PASSWORD)

    assert response.status_code == 302
    assert response.headers["Location"].endswith("/tasks")


def test_login_com_senha_errada_e_recusado(client):
    response = login(client, "admin", "senha-errada")

    assert response.status_code == 200
    assert "Usuario ou senha invalidos." in response.get_data(as_text=True)


@pytest.mark.parametrize(
    ("username", "password"),
    [(SQLI_LOGIN_PAYLOAD, "qualquer"), ("admin", SQLI_LOGIN_PAYLOAD)],
)
def test_login_resiste_a_sql_injection(client, username, password):
    response = login(client, username, password)

    assert response.status_code == 200
    with client.session_transaction() as session:
        assert "user_id" not in session


def test_senhas_sao_armazenadas_com_hash(client):
    with app.app_context():
        rows = get_db().execute("SELECT password FROM users").fetchall()

    assert rows
    for row in rows:
        assert row["password"] not in (ADMIN_PASSWORD, os.environ["TASKFLOW_ALUNO_PASSWORD"])
        assert row["password"].startswith("scrypt:")


def test_busca_resiste_a_sql_injection(client):
    login(client, "admin", ADMIN_PASSWORD)
    create_task(client, "tarefa do admin")

    response = client.get("/tasks", query_string={"q": "' OR '1'='1"})

    assert response.status_code == 200
    assert "tarefa do admin" not in response.get_data(as_text=True)


def test_busca_encontra_tarefa_pelo_titulo(client):
    login(client, "admin", ADMIN_PASSWORD)
    create_task(client, "comprar cafe")
    create_task(client, "estudar devsecops")

    body = client.get("/tasks", query_string={"q": "cafe"}).get_data(as_text=True)

    assert "comprar cafe" in body
    assert "estudar devsecops" not in body


def test_descricao_da_tarefa_e_escapada_contra_xss(client):
    login(client, "admin", ADMIN_PASSWORD)
    create_task(client, "tarefa", XSS_PAYLOAD)

    body = client.get("/tasks").get_data(as_text=True)

    assert XSS_PAYLOAD not in body
    assert "&lt;script&gt;" in body


def test_endpoint_de_debug_nao_existe(client):
    assert client.get("/debug/info").status_code == 404


def test_tarefas_exigem_login(client):
    response = client.get("/tasks")

    assert response.status_code == 302
    assert "/login" in response.headers["Location"]
