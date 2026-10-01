# Demonstração de shift-left

Objetivo: provar que uma vulnerabilidade introduzida em um Pull Request é **barrada antes de chegar na `main`**, sem depender de alguém lembrar de rodar uma ferramenta.

## Cenário

Um desenvolvedor "otimiza" a busca de tarefas montando a query por concatenação de string, exatamente a SQL Injection da linha de base:

```python
rows = db.execute(
    "SELECT * FROM tasks WHERE user_id = "
    + str(session["user_id"])
    + " AND title LIKE '%"
    + search
    + "%'"
).fetchall()
```

## Defesa em profundidade: três gates independentes pegam a mesma falha

| Check | Por que falha |
|---|---|
| `SAST - Semgrep` | regra `python.flask.security.injection.tainted-sql-string`: dado do usuário (`request.args`) chega no `db.execute` sem parametrização |
| `Lint (ruff)` | regra `S608` (Bandit): SQL montado por concatenação de string |
| `Testes (pytest)` | `test_busca_resiste_a_sql_injection`: o payload `' OR '1'='1` passa a devolver as tarefas |

Com esses checks marcados como *required* na proteção da `main`, o botão de merge fica bloqueado ("Merging is blocked"), inclusive para administradores (`enforce_admins`).

## Como reproduzir ao vivo

```bash
git switch main && git pull
git switch -c demo/shift-left-ao-vivo

# 1. introduz a falha (troca a busca parametrizada pela concatenada)
python3 - <<'EOF'
import pathlib
p = pathlib.Path("app.py")
s = p.read_text()
s = s.replace(
    '''        rows = db.execute(
            "SELECT * FROM tasks WHERE user_id = ? AND title LIKE ?",
            (session["user_id"], f"%{search}%"),
        ).fetchall()''',
    '''        rows = db.execute(
            "SELECT * FROM tasks WHERE user_id = "
            + str(session["user_id"])
            + " AND title LIKE '%"
            + search
            + "%'"
        ).fetchall()''',
)
p.write_text(s)
EOF
git commit -am "feat: simplifica a consulta da busca de tarefas"
git push -u origin demo/shift-left-ao-vivo
gh pr create --fill --base main

# 2. mostra os checks rodando e ficando vermelhos, e o merge bloqueado
gh pr checks --watch
gh pr merge --merge          # recusado: "the base branch policy prohibits the merge"

# 3. corrige (volta a consulta parametrizada) e mostra tudo verde
git revert --no-edit HEAD
git push
gh pr checks --watch
```

Depois da demo, feche o PR sem merge (`gh pr close --delete-branch`) ou faça o merge da versão corrigida.

> **Não** use um token "de teste" com formato real (`ghp_...`, `AKIA...`, `dckr_pat_...`) para demonstrar o Gitleaks: o professor procura esses padrões no histórico, e um token commitado, mesmo falso, gera o desconto de −2,0 da seção 4 das Rubricas Gerais. A SQL Injection demonstra o gate sem esse risco.
