#!/usr/bin/env bash
# Sobe a TaskFlow endurecida com flags de seguranca em tempo de execucao.
# Os segredos sao lidos do ambiente de quem executa (nunca ficam no script,
# na imagem ou na linha de comando do docker, visivel em "ps"):
#
#   export TASKFLOW_SECRET_KEY="$(openssl rand -hex 32)"
#   export TASKFLOW_ADMIN_PASSWORD='...'  TASKFLOW_ALUNO_PASSWORD='...'
#   scripts/docker-run-seguro.sh [imagem]

set -euo pipefail

: "${TASKFLOW_SECRET_KEY:?defina TASKFLOW_SECRET_KEY no ambiente}"
: "${TASKFLOW_ADMIN_PASSWORD:?defina TASKFLOW_ADMIN_PASSWORD no ambiente}"
: "${TASKFLOW_ALUNO_PASSWORD:?defina TASKFLOW_ALUNO_PASSWORD no ambiente}"

IMAGE="${1:-taskflow:hardened}"
CONTAINER_NAME="${CONTAINER_NAME:-taskflow-seguro}"
VOLUME_NAME="${VOLUME_NAME:-taskflow-dados}"
HOST_PORT="${HOST_PORT:-5000}"

docker volume create "$VOLUME_NAME" >/dev/null

# --read-only + volume/tmpfs: raiz somente leitura; so os dados e o /tmp sao gravaveis
# --cap-drop=ALL: nenhuma Linux capability (um servidor HTTP comum nao precisa)
# --security-opt=no-new-privileges: bloqueia escalada via binarios SUID
# --memory/--cpus/--pids-limit: limita o impacto de abuso de recursos
# --user: reforca o usuario nao-root mesmo que a imagem mude
# -e NOME (sem valor): repassa o segredo do ambiente sem expo-lo em "ps"
# 127.0.0.1: publica a porta so na interface local do host
docker run \
  --name "$CONTAINER_NAME" \
  --detach \
  --rm \
  --read-only \
  --volume "${VOLUME_NAME}:/app/data" \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --memory=256m \
  --cpus=0.5 \
  --pids-limit=100 \
  --user 65532:65532 \
  --publish "127.0.0.1:${HOST_PORT}:5000" \
  --env TASKFLOW_SECRET_KEY \
  --env TASKFLOW_ADMIN_PASSWORD \
  --env TASKFLOW_ALUNO_PASSWORD \
  "$IMAGE"

echo "Container '$CONTAINER_NAME' rodando em http://127.0.0.1:${HOST_PORT} (imagem $IMAGE)."
