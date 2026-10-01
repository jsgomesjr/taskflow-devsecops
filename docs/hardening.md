# Hardening — container e sistema operacional

Este documento registra o **antes × depois** do hardening da TaskFlow (Aula 3): o scan da imagem com Trivy, o `docker history`, a configuração do Dockerfile e a auditoria de SO com Lynis. As saídas completas das ferramentas estão em [`docs/evidencias/`](evidencias/).

| Medida | Antes (linha de base) | Depois |
|---|---|---|
| Trivy na imagem — SO (HIGH/CRITICAL) | **369** (350 HIGH, 19 CRITICAL) | **0** |
| Trivy na imagem — pacotes Python (HIGH/CRITICAL) | **14** (11 HIGH, 3 CRITICAL) | **0** |
| Trivy misconfig no Dockerfile | **4** (CRITICAL: segredo em ENV; HIGH: sem USER; MEDIUM: tag; LOW: sem HEALTHCHECK) | **0** (todas as severidades) |
| Segredo no `docker history` | `ENV ADMIN_PASSWORD=REDACTED` | nenhum |
| Tamanho da imagem | 1,65 GB | 122 MB |
| Usuário do processo | root (UID 0) | nonroot (UID 65532) |
| Shell / gerenciador de pacotes na imagem | sim / sim | não / não |
| Lynis — índice de hardening (SO de laboratório) | **57** | **82** |

## 1. Trivy na imagem — antes × depois

Comandos usados (iguais aos da aula, com a versão do Trivy fixada):

```bash
docker build -t taskflow:vuln .            # Dockerfile original (commit b323e5f)
docker build -t taskflow:hardened .        # Dockerfile atual
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.74.0 \
  image --severity HIGH,CRITICAL taskflow:vuln     > docs/evidencias/antes-trivy-image.txt
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.74.0 \
  image --severity HIGH,CRITICAL taskflow:hardened > docs/evidencias/depois-trivy-image.txt
```

**Antes** — [`antes-trivy-image.txt`](evidencias/antes-trivy-image.txt):

```text
taskflow:vuln (debian 13.7)
Total: 369 (HIGH: 350, CRITICAL: 19)

Python (python-pkg)
Total: 14 (HIGH: 11, CRITICAL: 3)
```

**Depois** — [`depois-trivy-image.txt`](evidencias/depois-trivy-image.txt):

```text
taskflow:hardened (wolfi 20230201)   wolfi        0
Python                               python-pkg   0
```

### Por que a imagem base mudou de `python:latest` para Chainguard

Medimos as candidatas com o mesmo Trivy, contando só HIGH/CRITICAL:

| Imagem base | HIGH/CRITICAL | Observação |
|---|---|---|
| `python:latest` (linha de base) | 369 | Debian completo, tag flutuante |
| `python:3.12-slim` / `python:3.13-slim` | 51 | a maioria sem correção disponível (`affected`) |
| `gcr.io/distroless/python3-debian13` | 26 | todas sem correção disponível |
| `cgr.dev/chainguard/python` (Wolfi) | **0** | sem shell e sem gerenciador de pacotes |

Com `slim` ou distroless, o gate só ficaria verde aceitando dezenas de CVEs no `.trivyignore` ou com `--ignore-unfixed`, ou seja, uma supressão em massa. A Chainguard elimina o problema na origem. O plano gratuito da Chainguard publica apenas a tag `latest`, por isso a imagem está **fixada por digest** (`@sha256:...`), o nível mais forte de pinning visto em aula: o digest é imutável e o build é reprodutível. O Dependabot (ecossistema `docker`) abre PR quando sai um digest novo, e o Trivy roda nesse PR antes do merge.

### Achados que apareceram no meio do caminho e foram corrigidos (não suprimidos)

A primeira versão endurecida ainda tinha **4 HIGH** (`msgpack`, `setuptools`, `urllib3`), que a aplicação nem usa. Eles vinham das dependências embutidas no **pip** que o `python -m venv` coloca dentro do venv. A correção foi criar o venv com `--without-pip` e instalar os pacotes com o pip do estágio de build (`pip --python /app/venv/bin/python install ...`). A imagem final ficou sem pip, o que zerou os achados e tirou do atacante o `pip install`.

## 2. `docker history` — antes × depois

**Antes** — [`antes-docker-history.txt`](evidencias/antes-docker-history.txt): o segredo aparece em texto puro em uma camada da imagem, e qualquer pessoa com acesso à imagem consegue lê-lo (o valor está como `REDACTED` nas evidências para não ser recommitado; `docker history --no-trunc taskflow:vuln` mostra o valor real):

```text
ENV ADMIN_PASSWORD=REDACTED
```

**Depois** — [`depois-docker-history.txt`](evidencias/depois-docker-history.txt): nenhuma camada contém segredo. A configuração gravada na imagem é só caminho e comportamento do Python:

```text
USER 65532:65532
ENV PATH=/app/venv/bin:... PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 TASKFLOW_DATABASE=/app/data/taskflow.db
```

`TASKFLOW_SECRET_KEY` e as senhas iniciais (`TASKFLOW_ADMIN_PASSWORD`, `TASKFLOW_ALUNO_PASSWORD`) são injetadas **em tempo de execução** por [`scripts/docker-run-seguro.sh`](../scripts/docker-run-seguro.sh), que as lê do ambiente de quem executa (`--env NOME`, sem valor na linha de comando, então elas não aparecem em `ps`). A regra customizada `dockerfile-secret-in-env-arg` do [`.gitleaks.toml`](../.gitleaks.toml) impede que um `ENV`/`ARG` com segredo volte ao Dockerfile.

## 3. Dockerfile — as seis falhas

| Falha original | Correção no [`Dockerfile`](../Dockerfile) |
|---|---|
| **1** — `FROM python:latest`, sem versão fixada | Imagem mínima Chainguard fixada por digest; build multi-stage (o estágio `-dev`, com pip, não vai para a imagem final) |
| **2** — roda como root | `USER 65532:65532` (nonroot); o script de execução reforça com `--user` |
| **3** — sem verificação de integridade das dependências | `requirements.txt` gerado com hashes (`pip-compile --generate-hashes`) e `pip install --require-hashes`: um pacote adulterado aborta o build |
| **4** — `ENV ADMIN_PASSWORD=REDACTED` | Nenhum segredo em `ENV`/`ARG`; segredos entram em runtime |
| **5** — porta do servidor de desenvolvimento | A porta 5000 é servida pelo gunicorn; `EXPOSE` só documenta |
| **6** — debug ligado / servidor de desenvolvimento | `ENTRYPOINT python -m gunicorn` com [`gunicorn.conf.py`](../gunicorn.conf.py); o modo debug foi removido do código |

Também entraram: `.dockerignore` com **lista positiva** (só `app.py`, `gunicorn.conf.py`, `requirements.txt` e `templates/` entram no contexto de build, então `.git`, `.env` e o banco local nunca vão parar na imagem) e `HEALTHCHECK`.

## 4. Flags de segurança em tempo de execução

[`scripts/docker-run-seguro.sh`](../scripts/docker-run-seguro.sh) (adaptado de `codigo/hardening/docker-run-seguro.sh`):

| Flag | Efeito |
|---|---|
| `--read-only` | raiz do container somente leitura |
| `--volume taskflow-dados:/app/data` e `--tmpfs /tmp:rw,noexec,nosuid` | os únicos caminhos graváveis: o banco SQLite e o `/tmp` |
| `--cap-drop=ALL` | nenhuma Linux capability |
| `--security-opt=no-new-privileges` | bloqueia escalada de privilégio via SUID |
| `--memory=256m --cpus=0.5 --pids-limit=100` | limita o abuso de recursos |
| `--user 65532:65532` | reforça o usuário não-root |
| `--publish 127.0.0.1:5000:5000` | publica a porta só na interface local do host |

O job **Container - build e Trivy** do [`container.yml`](../.github/workflows/container.yml) roda esse mesmo script no CI, com segredos aleatórios gerados no próprio job, e testa o login de verdade. Assim, se o hardening quebrar a aplicação, o PR também fica bloqueado.

Verificação local (saída real):

```text
$ scripts/docker-run-seguro.sh
GET /login -> 200
POST /login admin -> 302 http://127.0.0.1:5000/tasks
GET /debug/info -> 404
user=65532:65532 readonly=true caps=[ALL] health=healthy
$ docker exec taskflow-seguro sh -c id
exec: "sh": executable file not found in $PATH
```

## 5. Hardening de SO com Lynis

Para não auditar (e expor no repositório) a máquina pessoal de um membro do grupo, o "servidor" de laboratório é um **container Ubuntu 24.04 descartável**, fixado por digest, com OpenSSH e Lynis. [`hardening/so/auditar-lynis.sh`](../hardening/so/auditar-lynis.sh) audita duas vezes o mesmo ponto de partida:

- **antes**: só [`preparar-base.sh`](../hardening/so/preparar-base.sh) (instala SSH e Lynis, sobe o `sshd`);
- **depois**: base + [`aplicar-hardening.sh`](../hardening/so/aplicar-hardening.sh), em que cada bloco cita o ID do teste do Lynis que atende.

```bash
hardening/so/auditar-lynis.sh
# antes:  Hardening index : 57 [###########         ]
# depois: Hardening index : 82 [################    ]
```

Relatórios completos: [`lynis-antes.txt`](evidencias/lynis-antes.txt) e [`lynis-depois.txt`](evidencias/lynis-depois.txt).

### Achados corrigidos

| Teste Lynis | Achado | Correção |
|---|---|---|
| PKGS-7392 | pacotes com vulnerabilidade conhecida | `apt-get upgrade` |
| SSH-7408 | `MaxAuthTries 6`, `X11Forwarding`, `AllowTcpForwarding`, `AllowAgentForwarding`, `TCPKeepAlive`, `MaxSessions 10`, `LogLevel INFO`, `ClientAliveCountMax 3` | [`sshd_config.hardened`](../hardening/so/sshd_config.hardened) (base da disciplina + `MaxSessions`, `AllowTcpForwarding`, `TCPKeepAlive`, `Compression`, `Banner`): sem login de root, só chave pública, `AllowUsers aluno` |
| AUTH-9230 / 9286 / 9328 | rounds do hash de senha, idade de senha, `UMASK 022` | `/etc/login.defs`: `SHA_CRYPT_*_ROUNDS`, `PASS_MAX_DAYS 90`, `PASS_MIN_DAYS 1`, `UMASK 027` |
| AUTH-9262 | sem módulo de força de senha | `libpam-pwquality` |
| KRNL-5820 | core dumps habilitados | `* hard core 0` |
| NETW-3200, USB-1000, STRG-1846 | `dccp`, `sctp`, `rds`, `tipc`, USB e FireWire storage disponíveis | bloqueados em `/etc/modprobe.d/90-hardening.conf` |
| BANN-7126 / 7130 | sem aviso legal | `/etc/issue` e `/etc/issue.net` |
| FINT-4350 / 4316 / 4402 | sem monitor de integridade de arquivos | AIDE com base inicializada e checksum SHA-512 |
| HRDN-7230 | sem scanner de malware | `rkhunter` |
| DEB-0280, DEB-0811, DEB-0831, DEB-0880 | `libpam-tmpdir`, `apt-listchanges`, `needrestart`, `fail2ban` | instalados (`fail2ban` com `jail.local`) |
| PKGS-7370 / 7394 / 7420 | integridade e gestão de patches | `debsums`, `apt-show-versions`, `unattended-upgrades` |
| ACCT-9622 / 9626 | sem contabilidade de processos / estatísticas | `acct`, `sysstat` habilitado |
| FILE-7524 | permissões frouxas | `chmod 600` em arquivos sensíveis existentes |

### Achados restantes e por que foram aceitos

| Teste Lynis | Motivo |
|---|---|
| KRNL-6000 (sysctl), KRNL-5788 (`/vmlinuz`), BOOT-5180 / 5264 | Em container o kernel e o boot são do **host**; sysctl e serviços de boot se endurecem no host, não na imagem. |
| FILE-6310 (`/home`, `/tmp`, `/var` em partições separadas) | Não se aplica a container; em VM ou servidor físico, faz parte do particionamento na instalação. |
| LOGG-2130 / 2138 (syslog, klogd), ACCT-9628 (auditd) | Container não roda init nem syslog; logs vão para o stdout do runtime, e o auditd depende do subsistema de auditoria do kernel do host. |
| SSH-7408 (`Port 22`) | Mudar a porta é segurança por obscuridade e não está no CIS Benchmark. Mantivemos 22, e a proteção real vem de não aceitar senha nem root, mais o fail2ban. |
| AUTH-9284 (contas bloqueadas) | São as contas de sistema do Ubuntu (bloqueadas por design). |
| DEB-0810 (`apt-listbugs`) | O pacote não existe no Ubuntu (ele consulta o bug tracker do Debian). |
| NAME-4028, TOOL-5002, LYNIS (versão antiga) | Laboratório sem domínio DNS e sem ferramenta de automação; usamos o Lynis do repositório oficial do Ubuntu (3.0.9) para a auditoria ser reproduzível. |
