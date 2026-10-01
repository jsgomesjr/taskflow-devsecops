# TaskFlow DevSecOps

[![CI](https://github.com/jsgomesjr/taskflow-devsecops/actions/workflows/ci.yml/badge.svg)](https://github.com/jsgomesjr/taskflow-devsecops/actions/workflows/ci.yml)
[![SAST](https://github.com/jsgomesjr/taskflow-devsecops/actions/workflows/sast.yml/badge.svg)](https://github.com/jsgomesjr/taskflow-devsecops/actions/workflows/sast.yml)
[![SCA](https://github.com/jsgomesjr/taskflow-devsecops/actions/workflows/sca.yml/badge.svg)](https://github.com/jsgomesjr/taskflow-devsecops/actions/workflows/sca.yml)
[![Container](https://github.com/jsgomesjr/taskflow-devsecops/actions/workflows/container.yml/badge.svg)](https://github.com/jsgomesjr/taskflow-devsecops/actions/workflows/container.yml)

**Atividade 1 — Lab de Esteira Segura** (DevSecOps, Pós-Graduação em DevOps, CESAR School).

A TaskFlow, aplicação Flask propositalmente vulnerável da disciplina, protegida por uma esteira de CI no GitHub Actions que funciona como *quality gate*: build, lint, testes, SAST, secret scanning, SCA e hardening da imagem rodam em todo Pull Request, e **nenhum merge na `main` acontece com um gate vermelho**.

**Grupo:** [@jsgomesjr](https://github.com/jsgomesjr) · [@AlanGarci4](https://github.com/AlanGarci4) · [@danielarrais](https://github.com/danielarrais) · [@tuliocoimbra](https://github.com/tuliocoimbra)

## Sumário

- [A esteira](#a-esteira)
- [Proteção da `main`](#protecao-da-main)
- [O que foi corrigido na TaskFlow](#o-que-foi-corrigido-na-taskflow)
- [Como rodar a aplicação](#como-rodar-a-aplicacao)
- [Como rodar cada scanner localmente](#como-rodar-cada-scanner-localmente)
- [Como disparar os workflows](#como-disparar-os-workflows)
- [Decisões técnicas e aceites de risco](#decisoes-tecnicas-e-aceites-de-risco)
- [Evidências](#evidencias)
- [Estrutura do repositório](#estrutura-do-repositorio)
- [Reaproveitamento do material da disciplina](#reaproveitamento-do-material-da-disciplina)

## A esteira

Os quatro workflows disparam em `pull_request` para a `main`, em `push` na `main` e em `workflow_dispatch`.

| Workflow | Job (nome do check) | O que faz | Bloqueia quando |
|---|---|---|---|
| [`ci.yml`](.github/workflows/ci.yml) | `Lint (ruff)` | `ruff check` (inclui as regras de segurança do Bandit, `S`) e `ruff format --check` | erro de lint, de segurança ou de formatação |
| | `Testes (pytest)` | 10 testes: login, hash de senha, SQLi no login e na busca, XSS, `/debug/info` | qualquer teste falha |
| [`sast.yml`](.github/workflows/sast.yml) | `SAST - Semgrep` | Semgrep com `p/python`, `p/flask` e `p/security-audit`, com `--error` | qualquer achado |
| | `Secret Scanning - Gitleaks` | Gitleaks em **todo o histórico** (`fetch-depth: 0`), com regras padrão + [`.gitleaks.toml`](.gitleaks.toml) | qualquer segredo fora da allowlist justificada |
| [`sca.yml`](.github/workflows/sca.yml) | `SCA - pip-audit (requirements.txt)` e `(requirements-dev.txt)` | pip-audit contra a base da PyPA | qualquer CVE conhecida |
| | `SCA - Trivy (dependencias)` | `trivy fs` nos manifestos de dependência | CVE HIGH ou CRITICAL |
| [`container.yml`](.github/workflows/container.yml) | `Container - build e Trivy` | build da imagem, `trivy image`, `trivy` misconfig no Dockerfile e teste da imagem rodando com as flags seguras | CVE ou misconfig HIGH/CRITICAL, ou a aplicação não sobe |

Além dos gates, o [Dependabot](.github/dependabot.yml) monitora toda semana as dependências **pip**, as **GitHub Actions** (inclusive as actions compostas locais) e a **imagem Docker**, e abre PRs que passam pela mesma esteira.

**Boas práticas de pipeline as code aplicadas:**

- `permissions: contents: read` em todos os workflows (mínimo; nenhum job escreve no repositório) e `persist-credentials: false` no checkout.
- Toda action de terceiros fixada por **SHA de commit** (com a versão em comentário); imagens de ferramentas (Semgrep, Gitleaks) fixadas por **digest**.
- **DRY**: duas actions compostas locais concentram o que se repete.
  - [`.github/actions/setup-python`](.github/actions/setup-python/action.yml) configura o Python, com a versão lida de [`.python-version`](.python-version) (fonte única), e instala dependências com `--require-hashes`.
  - [`.github/actions/trivy-scan`](.github/actions/trivy-scan/action.yml) é o único lugar com a versão do Trivy e a severidade de corte (`HIGH,CRITICAL`).
- Nada fixo espalhado pelo YAML: as versões das ferramentas, a imagem e o caminho do Dockerfile ficam em `env:` no topo de cada workflow; a matriz de requirements está no `strategy.matrix`.
- `concurrency` cancela execuções obsoletas do mesmo branch; `timeout-minutes` em todo job.
- Nenhum `continue-on-error`, `--exit-zero` ou `soft_fail` em lugar nenhum.

## Proteção da `main`

Configurada em *Settings → Branches* (regra clássica para `main`):

- **Pull Request obrigatório** antes do merge (push direto na `main` é recusado).
- **Required status checks**, com o branch atualizado (`strict`): `Lint (ruff)`, `Testes (pytest)`, `SAST - Semgrep`, `Secret Scanning - Gitleaks`, `SCA - pip-audit (requirements.txt)`, `SCA - pip-audit (requirements-dev.txt)`, `SCA - Trivy (dependencias)` e `Container - build e Trivy`.
- **CODEOWNERS** ([`.github/CODEOWNERS`](.github/CODEOWNERS)) com os quatro membros e **revisão de code owner obrigatória**.
- **Regras valem também para administradores** (`enforce_admins`): nem o dono do repositório consegue mesclar com um check vermelho.
- Conversas resolvidas obrigatórias, sem force-push e sem exclusão da `main`.

Para conferir: `gh api repos/jsgomesjr/taskflow-devsecops/branches/main/protection`.

## O que foi corrigido na TaskFlow

| # | Vulnerabilidade da linha de base | Quem detectou | Correção | Prova |
|---|---|---|---|---|
| 1 | SQL Injection no login e na busca (concatenação de string) | Semgrep `tainted-sql-string` | Consultas parametrizadas (`?`) em [`app.py`](app.py) | `test_login_resiste_a_sql_injection`, `test_busca_resiste_a_sql_injection` |
| 2 | XSS armazenado na descrição da tarefa (HTML montado em f-string) | Semgrep `raw-html-format`, `directly-returned-format-string` | Templates Jinja2 com autoescape em [`templates/`](templates) | `test_descricao_da_tarefa_e_escapada_contra_xss` |
| 3 | `SECRET_KEY` hardcoded | Semgrep `avoid_hardcoded_config_SECRET_KEY`, Gitleaks (regra customizada) | Lida de `TASKFLOW_SECRET_KEY`; a aplicação **recusa iniciar** se a variável não existir | — |
| 4 | Senhas em texto puro no banco | Revisão de código | Hash **scrypt** (`werkzeug.security`); senhas iniciais vêm do ambiente (`TASKFLOW_ADMIN_PASSWORD`, `TASKFLOW_ALUNO_PASSWORD`) | `test_senhas_sao_armazenadas_com_hash` |
| 5 | `/debug/info` público, vazando a `SECRET_KEY` | Revisão de código | Endpoint removido | `test_endpoint_de_debug_nao_existe` |
| 6 | `debug=True` e `host="0.0.0.0"` | Semgrep `debug-enabled`, `avoid_app_run_with_bad_host` | Sem debug; execução local em `127.0.0.1`; no container, gunicorn | — |
| 7 | Dependências com CVE (Flask 0.12.2, Werkzeug 0.15.4, PyYAML 5.1, requests 2.6.0, Jinja2 2.11.3) | pip-audit (50 CVEs em 5 pacotes), Trivy fs (10 HIGH/CRITICAL) | Versões atuais, com hashes; PyYAML e requests removidos (a aplicação não os importa) | `pip-audit`: *No known vulnerabilities found* |
| 8 | Dockerfile com as FALHAS 1 a 6 | Trivy image (383 HIGH/CRITICAL) e Trivy misconfig (4) | Ver [`docs/hardening.md`](docs/hardening.md) | `trivy image`: 0 |

Também entraram `session.clear()` antes de autenticar (contra fixação de sessão) e um login que não revela se o usuário existe.

## Como rodar a aplicação

Pré-requisitos: Python 3.14 (versão em [`.python-version`](.python-version)) e Docker.

### Localmente

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --require-hashes -r requirements.txt -r requirements-dev.txt

export TASKFLOW_SECRET_KEY="$(python -c 'import secrets; print(secrets.token_hex(32))')"
export TASKFLOW_ADMIN_PASSWORD='escolha-uma-senha'
export TASKFLOW_ALUNO_PASSWORD='escolha-outra-senha'
python app.py
```

A aplicação sobe em <http://127.0.0.1:5000>, com os usuários `admin` e `aluno` e as senhas definidas acima. Os segredos ficam só no seu shell; um arquivo `.env`, se for usado, está no [`.gitignore`](.gitignore) e nunca deve ser versionado.

### Com Docker (imagem endurecida e flags seguras)

```bash
docker build -t taskflow:hardened .
export TASKFLOW_SECRET_KEY="$(openssl rand -hex 32)"
export TASKFLOW_ADMIN_PASSWORD='escolha-uma-senha' TASKFLOW_ALUNO_PASSWORD='escolha-outra-senha'
scripts/docker-run-seguro.sh            # sobe em http://127.0.0.1:5000
docker logs -f taskflow-seguro
docker stop taskflow-seguro
```

### Testes e lint

```bash
ruff check . && ruff format --check .
pytest -v
```

## Como rodar cada scanner localmente

Os comandos usam as mesmas versões fixadas na esteira, via Docker, sem instalar nada na máquina.

```bash
# SAST - Semgrep (mesmos rulesets e --error da esteira)
docker run --rm -v "$PWD:/src" -w /src semgrep/semgrep:1.178.0 \
  semgrep scan --config=p/python --config=p/flask --config=p/security-audit --error --metrics=off

# Secret scanning - Gitleaks em todo o historico, com as regras e a allowlist do repositorio
docker run --rm -v "$PWD:/repo" ghcr.io/gitleaks/gitleaks:v8.30.1 \
  git /repo --config /repo/.gitleaks.toml --redact --verbose

# SCA - pip-audit (um arquivo por vez, como na matriz da esteira)
pip install pip-audit==2.10.1
pip-audit --strict -r requirements.txt
pip-audit --strict -r requirements-dev.txt

# SCA - Trivy nas dependencias
docker run --rm -v "$PWD:/projeto" aquasec/trivy:0.74.0 \
  fs --scanners vuln --severity HIGH,CRITICAL --exit-code 1 /projeto

# Container - build, Trivy na imagem e misconfig do Dockerfile
docker build -t taskflow:hardened .
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.74.0 \
  image --severity HIGH,CRITICAL --exit-code 1 taskflow:hardened
docker run --rm -v "$PWD:/projeto" aquasec/trivy:0.74.0 \
  fs --scanners misconfig --severity HIGH,CRITICAL --exit-code 1 /projeto
docker history --no-trunc taskflow:hardened

# Hardening de SO - Lynis antes x depois (grava em docs/evidencias/)
hardening/so/auditar-lynis.sh
```

### Atualizar dependências

O `requirements.txt` e o `requirements-dev.txt` são gerados a partir dos `.in` com hashes (o Dependabot sabe atualizar esse formato):

```bash
pip install pip-tools==7.6.1
pip-compile --upgrade --generate-hashes --strip-extras --allow-unsafe requirements.in
pip-compile --upgrade --generate-hashes --strip-extras --allow-unsafe requirements-dev.in
```

## Como disparar os workflows

- **Automaticamente**: abrindo ou atualizando um Pull Request para a `main` (os quatro workflows rodam e viram checks do PR) e a cada push na `main` (após o merge).
- **Manualmente**: aba *Actions* → escolha o workflow (CI, SAST, SCA ou Container) → *Run workflow* → branch. Pela linha de comando:

```bash
gh workflow run ci.yml --ref main
gh workflow run sast.yml --ref main
gh workflow run sca.yml --ref main
gh workflow run container.yml --ref main
gh run list --limit 8
```

Nenhum workflow precisa de *secret* configurado: não há credencial na esteira. O Gitleaks roda pela imagem oficial e o Trivy baixa sua base pública.

## Decisões técnicas e aceites de risco

1. **Gitleaks: regras customizadas + allowlist justificada.** As regras padrão do Gitleaks **não detectam** a `SECRET_KEY` e o `ADMIN_PASSWORD` didáticos, por terem entropia baixa (veja [`antes-gitleaks.txt`](docs/evidencias/antes-gitleaks.txt)). Por isso criamos duas regras no [`.gitleaks.toml`](.gitleaks.toml): `SECRET_KEY` literal no Flask e segredo em `ENV`/`ARG` de Dockerfile. Elas acusaram os dois valores no commit da linha de base `b323e5f`, que está no histórico por design (exceção prevista na seção 2c das Rubricas Gerais). Os valores foram removidos do código atual, e a allowlist exige **ao mesmo tempo** (`condition = "AND"`) aquele commit, um dos dois arquivos originais (`app.py`, `Dockerfile`) e uma das duas regras do grupo, sem guardar os valores em texto puro. Qualquer outro segredo, inclusive no mesmo commit, continua reprovando o gate, e a regra e o job não foram desligados. Nas evidências e na documentação, os valores didáticos aparecem como `REDACTED`, para não serem recommitados; as regras do grupo ignoram só esse marcador exato.
2. **Semgrep: um falso positivo, suprimido com justificativa.** A regra `avoid_hardcoded_config_TESTING` acusou `TESTING=True` no **fixture do pytest** ([`test_app.py`](test_app.py)). Ela existe para proteger a configuração de produção; ligar `TESTING` no fixture de teste é exatamente o uso previsto da flag, e esse código nunca é carregado pela aplicação. A supressão é por ID de regra, numa única linha, com a justificativa no comentário ao lado. Nenhuma outra supressão existe no repositório (`.trivyignore` está vazio).
3. **Imagem base Chainguard fixada por digest.** `slim` e distroless deixavam 51 e 26 HIGH sem correção disponível, que só passariam no gate com supressão em massa; a Chainguard tem 0. O plano gratuito só publica a tag `latest`, então o pin é por **digest**, o nível mais forte (comparativo em [`docs/hardening.md`](docs/hardening.md)).
4. **Python 3.14.** É a versão da imagem Chainguard. Usar a mesma versão em CI, testes e imagem evita o "funciona no CI, quebra no container"; a versão fica em um só lugar, [`.python-version`](.python-version).
5. **Dependências com hashes e só o necessário.** `pip install --require-hashes` corrige a FALHA 3 e protege contra pacote adulterado no índice. PyYAML e requests saíram porque a aplicação não os importa: dependência não usada é só superfície de ataque.
6. **Repositório público em vez de privado.** O enunciado pede repositório privado, mas o GitHub recusa branch protection em repositório privado de conta gratuita (`HTTP 403: Upgrade to GitHub Pro or make this repository public to enable this feature`). Como o gate de merge é o centro da atividade, o grupo optou por deixar o repositório público para manter a proteção real da `main`. Não há nenhum segredo real no repositório, só os valores didáticos já públicos no repositório da disciplina. O professor (@HardSource) é colaborador com permissão de leitura.
7. **Lynis em container descartável.** O "servidor" auditado é um Ubuntu 24.04 em container, para que a auditoria seja reproduzível por qualquer membro e não exponha dados da máquina pessoal de ninguém. Os achados que só existem no host (kernel, partições, syslog) estão listados como aceitos em [`docs/hardening.md`](docs/hardening.md#achados-restantes-e-por-que-foram-aceitos).
8. **Merge commit, e não squash.** Preserva na `main` os commits pequenos de cada PR (primeiro o gate entra e falha, depois vem cada correção), que contam a história da esteira.

## Evidências

- **Gates bloqueando antes da correção** (o workflow entrou primeiro, sozinho, contra o código original):
  - SCA: [run vermelho no PR #2](https://github.com/jsgomesjr/taskflow-devsecops/actions/runs/36891421760): pip-audit encontrou 50 CVEs em 5 pacotes, Trivy encontrou 10 HIGH/CRITICAL.
  - SAST: [run vermelho no PR #3](https://github.com/jsgomesjr/taskflow-devsecops/actions/runs/36892076086): Semgrep com 10 achados bloqueantes, Gitleaks com 2 segredos.
  - Container: [run vermelho no PR #4](https://github.com/jsgomesjr/taskflow-devsecops/actions/runs/36892950504): Trivy com 369 + 4 HIGH/CRITICAL.
- **Gates verdes após a correção**: checks dos PRs [#1](https://github.com/jsgomesjr/taskflow-devsecops/pull/1), [#2](https://github.com/jsgomesjr/taskflow-devsecops/pull/2), [#3](https://github.com/jsgomesjr/taskflow-devsecops/pull/3) e [#4](https://github.com/jsgomesjr/taskflow-devsecops/pull/4), e a [aba Actions](https://github.com/jsgomesjr/taskflow-devsecops/actions).
- **Demonstração de shift-left** (vulnerabilidade introduzida em PR, merge bloqueado, correção): [`docs/shift-left.md`](docs/shift-left.md).
- **Saídas completas das ferramentas, antes × depois**: [`docs/evidencias/`](docs/evidencias).
- **Hardening de container e de SO** (Trivy, `docker history`, Lynis): [`docs/hardening.md`](docs/hardening.md).
- **Roteiro da apresentação**: [`docs/apresentacao.md`](docs/apresentacao.md).

## Estrutura do repositório

```text
.
├── app.py                      # aplicacao Flask corrigida
├── templates/                  # HTML com autoescape do Jinja2
├── test_app.py, conftest.py    # testes (pytest)
├── gunicorn.conf.py            # servidor WSGI de producao
├── Dockerfile, .dockerignore   # imagem endurecida
├── requirements*.in / *.txt    # dependencias (txt gerado com hashes)
├── ruff.toml                   # lint, incluindo as regras de seguranca (Bandit)
├── .gitleaks.toml              # regras customizadas + allowlist justificada
├── .trivyignore                # achados aceitos do Trivy (vazio)
├── .python-version             # versao unica do Python
├── scripts/docker-run-seguro.sh
├── hardening/so/               # hardening de SO auditado com Lynis
├── docs/                       # hardening, shift-left, apresentacao, evidencias
└── .github/
    ├── workflows/              # ci.yml, sast.yml, sca.yml, container.yml
    ├── actions/                # actions compostas: setup-python, trivy-scan
    ├── dependabot.yml
    ├── CODEOWNERS
    └── pull_request_template.md
```

## Reaproveitamento do material da disciplina

Os arquivos de `codigo/` do [repositório da disciplina](https://github.com/diegobuarquebr/taskflow_pos_2026) serviram de ponto de partida e foram adaptados:

- `ci-basico.yml` virou o [`ci.yml`](.github/workflows/ci.yml), com ruff no lugar do `py_compile`, job de testes e a action composta de Python.
- `sast.yml` foi mantido com os mesmos rulesets e o `--error`; o Gitleaks passou a rodar pela imagem oficial fixada por digest, com o `.gitleaks.toml` do grupo.
- `sca.yml` virou uma matriz por arquivo de requirements, mais o Trivy fs como segunda fonte de vulnerabilidades.
- `dependabot.yml` ganhou o ecossistema `docker` e as actions compostas locais.
- `Dockerfile.hardened` foi a referência das correções; a imagem base e o venv sem pip foram decisão do grupo, depois de medir com o Trivy.
- `docker-run-seguro.sh` manteve as flags e passou a ler os segredos do ambiente; ele também é reaproveitado pelo job de container para testar a imagem no CI.
- `sshd_config.hardened` é a base do [`hardening/so/sshd_config.hardened`](hardening/so/sshd_config.hardened).
