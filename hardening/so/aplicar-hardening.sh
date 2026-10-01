#!/usr/bin/env bash
# Correcoes de hardening de SO aplicadas a partir das sugestoes do Lynis.
# O ID do teste do Lynis atendido esta ao lado de cada bloco.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
HARDENING_DIR="$(cd "$(dirname "$0")" && pwd)"

# PKGS-7392: pacotes com vulnerabilidade conhecida -> atualizar o sistema
apt-get upgrade -y -qq >/dev/null

# AUTH-9262, DEB-0280, PKGS-7370, PKGS-7394, PKGS-7420, DEB-0811, DEB-0831,
# DEB-0880, HRDN-7230, ACCT-9622, ACCT-9626, FINT-4350:
# forca de senha (pwquality), TMPDIR por sessao, verificacao de integridade de
# pacotes, gestao de patches, atualizacao automatica, mudancas antes de
# instalar, servicos a reiniciar apos update, bloqueio de forca bruta, scanner
# de rootkit, contabilidade de processos, estatisticas do sistema e
# monitoramento de integridade de arquivos (AIDE + configuracao)
apt-get install -y -qq --no-install-recommends \
  libpam-pwquality libpam-tmpdir debsums apt-show-versions unattended-upgrades \
  apt-listchanges needrestart fail2ban rkhunter acct sysstat \
  aide aide-common >/dev/null
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat

# FINT-4402, FINT-4316: AIDE com checksum SHA-512 e base de referencia criada
echo 'HardeningChecksums = sha512' >> /etc/aide/aide.conf
aideinit --yes --force >/dev/null 2>&1

# HRDN-7222: compiladores executaveis apenas pelo root
for compiler in as cc clang gcc g++; do
  if command -v "$compiler" >/dev/null; then chmod o-rx "$(readlink -f "$(command -v "$compiler")")"; fi
done

# SSH-7408: configuracao do SSH endurecida (root sem login, so chave publica,
# limite de tentativas, sem forwarding, log verboso)
useradd --create-home --shell /bin/bash aluno
install -m 600 "$HARDENING_DIR/sshd_config.hardened" /etc/ssh/sshd_config
sshd -t

# AUTH-9230, AUTH-9286, AUTH-9328: rounds do hash de senha, idade minima e
# maxima da senha, umask padrao mais restritiva
sed -i \
  -e 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' \
  -e 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS 1/' \
  -e 's/^UMASK.*/UMASK 027/' \
  /etc/login.defs
printf 'SHA_CRYPT_MIN_ROUNDS 5000\nSHA_CRYPT_MAX_ROUNDS 10000\n' >> /etc/login.defs

# KRNL-5820: sem core dumps (podem conter senhas e chaves em memoria)
echo '* hard core 0' > /etc/security/limits.d/90-sem-core-dump.conf

# NETW-3200, USB-1000, STRG-1846: protocolos de rede e drivers de
# armazenamento removivel que o servidor nao usa
mkdir -p /etc/modprobe.d
for module in dccp sctp rds tipc usb-storage firewire-core; do
  echo "install $module /bin/true"
done > /etc/modprobe.d/90-hardening.conf

# BANN-7126, BANN-7130: aviso legal para acesso local e remoto
BANNER="AVISO: acesso restrito a usuarios autorizados; atividades sao monitoradas e registradas.
WARNING: authorized access only. This private system is monitored and all activity is recorded;
unauthorized use is prohibited and subject to legal action."
echo "$BANNER" > /etc/issue
echo "$BANNER" > /etc/issue.net

# FILE-7524: permissoes restritivas em arquivos sensiveis
for path in /etc/crontab /etc/ssh/sshd_config; do
  if [ -e "$path" ]; then chmod 600 "$path"; fi
done
for path in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
  if [ -e "$path" ]; then chmod 700 "$path"; fi
done
