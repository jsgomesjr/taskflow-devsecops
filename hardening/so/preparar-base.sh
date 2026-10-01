#!/usr/bin/env bash
# Prepara o "servidor" de laboratorio: Ubuntu 24.04 com SSH e Lynis.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends lynis openssh-server >/dev/null
mkdir -p /run/sshd
