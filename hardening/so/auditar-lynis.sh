#!/usr/bin/env bash
# Audita com o Lynis o mesmo "servidor" Ubuntu 24.04 antes e depois do hardening,
# cada um em um container descartavel, e grava os relatorios em docs/evidencias/.
#
#   hardening/so/auditar-lynis.sh
set -euo pipefail

BASE_IMAGE="ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EVIDENCE_DIR="$ROOT_DIR/docs/evidencias"
AUDIT="/usr/sbin/sshd && lynis audit system --quick --no-colors"

run_audit() {
  local scenario="$1" steps="$2"
  docker run --rm \
    --volume "$ROOT_DIR/hardening/so:/hardening:ro" \
    "$BASE_IMAGE" \
    bash -c "$steps && $AUDIT" > "$EVIDENCE_DIR/lynis-$scenario.txt" 2>&1
  grep "Hardening index" "$EVIDENCE_DIR/lynis-$scenario.txt" | sed "s/^ */$scenario: /"
}

mkdir -p "$EVIDENCE_DIR"
run_audit antes "/hardening/preparar-base.sh"
run_audit depois "/hardening/preparar-base.sh && /hardening/aplicar-hardening.sh"
