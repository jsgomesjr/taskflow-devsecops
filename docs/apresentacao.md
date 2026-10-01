# Roteiro da apresentação (~10 minutos)

O enunciado pede para mostrar **o repositório, os PRs e a aba Actions, não slides**. Cada bloco abaixo diz o que abrir na tela. A divisão entre os membros é uma sugestão: o grupo ajusta, desde que **todos falem**.

Antes de começar, deixe abertos: o repositório, a aba *Actions*, *Settings → Branches* e um terminal na `main` atualizada.

| Tempo | Bloco | Quem (sugestão) | O que mostrar |
|---|---|---|---|
| 0:00–1:00 | 1. Contexto | membro 1 | README: objetivo, membros e papéis, tabela da esteira |
| 1:00–5:00 | 2. Demo ao vivo | membros 2 e 3 | PR com SQL Injection → checks vermelhos → merge bloqueado → correção → verde |
| 5:00–7:00 | 3. Antes × depois | membro 4 | runs vermelhos dos PRs #2, #3 e #4; `docs/hardening.md` |
| 7:00–8:30 | 4. Decisão técnica | membro 1 | allowlist do Gitleaks e falso positivo do Semgrep |
| 8:30–10:00 | 5. Aprendizado | todos (uma frase cada) | — |

## 1. Contexto (1 min)

- TaskFlow: app Flask **propositalmente vulnerável** (SQLi, XSS, segredo hardcoded, senha em texto puro, debug exposto, dependências com CVE e Dockerfile inseguro).
- Objetivo: uma esteira que **impede** código e configuração inseguros de entrarem na `main`.
- Mostrar *Settings → Branches*: PR obrigatório, 8 required checks, CODEOWNERS, regras valendo para admin.

## 2. Demo ao vivo (4 min)

Siga o passo a passo de [`shift-left.md`](shift-left.md#como-reproduzir-ao-vivo). O que falar enquanto os checks rodam (~1 min):

- "Três gates independentes pegam a mesma falha: o **Semgrep** (taint de `request.args` até o `db.execute`), o **ruff** com as regras do Bandit (S608) e o **teste** de SQL Injection."
- No PR: botão de merge bloqueado. Rodar `gh pr merge` e mostrar a recusa.
- Corrigir com `git revert`, push, e mostrar tudo verde.

Plano B, caso a rede ou o GitHub falhem: o PR de demonstração já registrado em [`shift-left.md`](shift-left.md#execucao-registrada), com os runs vermelho e verde.

## 3. Antes × depois (2 min)

| Ferramenta | Antes | Depois |
|---|---|---|
| Semgrep | 10 achados bloqueantes | 0 (1 falso positivo justificado) |
| Gitleaks | 2 segredos (com as regras do grupo) | 0 fora da allowlist justificada |
| pip-audit | 50 CVEs em 5 pacotes | 0 |
| Trivy fs | 10 HIGH/CRITICAL | 0 |
| Trivy image | 383 HIGH/CRITICAL, imagem de 1,65 GB | 0, imagem de 122 MB |
| Trivy misconfig (Dockerfile) | 4 (1 CRITICAL, 1 HIGH) | 0 |
| `docker history` | `ENV ADMIN_PASSWORD=REDACTED` | nenhum segredo |
| Lynis | índice 57 | índice 82 |

Mostrar os runs vermelhos linkados no README (seção Evidências): em cada PR o workflow entrou primeiro, sozinho, e falhou contra o código original.

## 4. Decisão técnica (1,5 min) — escolher uma

- **Gitleaks não detectava os segredos didáticos.** As regras padrão ignoram valores de entropia baixa. O grupo criou regras para `SECRET_KEY` e `ENV`/`ARG` de Dockerfile e aceitou só os achados delas no commit da linha de base e nos dois arquivos originais (`condition = "AND"`); um segredo novo é bloqueado. Não desligamos a regra nem o job.
- **Falso positivo do Semgrep.** `TESTING=True` no fixture do pytest: a regra protege a configuração de produção, e o fixture nunca roda em produção. A supressão é por ID de regra, com justificativa ao lado.
- **Chainguard em vez de `slim`.** `slim` deixava 51 HIGH sem correção; o gate só passaria com supressão em massa. A Chainguard tem 0, fixada por digest.

## 5. Aprendizado mais impactante (1,5 min)

Sugestões (cada membro escolhe a sua):

- Um scanner verde só vale se o verde for honesto: corrigir a causa (o venv sem pip zerou 4 CVEs) em vez de suprimir.
- O segredo commitado continua no histórico; o gate precisa olhar o histórico inteiro (`fetch-depth: 0`).
- Sem *required checks*, o pipeline vermelho é decorativo.

## Perguntas prováveis na arguição

| Pergunta | Resposta curta |
|---|---|
| Por que `fetch-depth: 0` no Gitleaks? | Para varrer o histórico inteiro; segredo removido do arquivo continua nos commits antigos. |
| Por que fixar actions por SHA e não por tag? | A tag pode ser movida para um commit malicioso (ataque de cadeia de suprimentos); o SHA é imutável. |
| Por que `permissions: contents: read`? | Menor privilégio: o `GITHUB_TOKEN` do job não consegue escrever no repositório nem abrir PR, mesmo se uma action for comprometida. |
| O que o `--require-hashes` protege? | Se o pacote baixado não tiver o hash registrado no `requirements.txt` (adulterado ou trocado no índice), o `pip` aborta. |
| Por que a aplicação recusa iniciar sem `TASKFLOW_SECRET_KEY`? | Falhar alto é melhor que cair em silêncio para um valor fixo, o que reintroduziria o segredo hardcoded. |
| Por que scrypt? | É um hash lento e com custo de memória; dificulta força bruta offline se o banco vazar. |
| Por que os templates resolvem o XSS? | O Jinja2 escapa `<`, `>`, `&`, `'` e `"` por padrão; o HTML em f-string não escapa nada. |
| O que muda com `--read-only` e `--cap-drop=ALL`? | O atacante não consegue alterar binários nem persistir nada na imagem, e o processo não tem nenhuma capability do kernel. |
| Por que o repositório é público? | Branch protection em repositório privado exige GitHub Pro; sem ela o gate seria decorativo. Não há segredo real no repositório. |
