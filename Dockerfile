# Dockerfile endurecido da TaskFlow. Cada "FALHA N" corresponde a falha de
# mesmo numero do Dockerfile original; o antes x depois esta em docs/hardening.md.

# FALHA 1 (tag latest sem fixar): imagem base minima Chainguard/Wolfi, fixada
# por digest imutavel. O runtime nao tem shell nem gerenciador de pacotes.
# O estagio de build usa a variante -dev (com pip), que nao vai para a imagem final.
FROM cgr.dev/chainguard/python:latest-dev@sha256:83933e374c3c3250e5b1b5dcde789a2d4a7314b771618b5548adab01c54066a0 AS build

WORKDIR /app
# O venv da aplicacao e criado sem pip: o pip do estagio de build instala os
# pacotes nele, e a imagem final nao carrega gerenciador de pacotes nem as
# dependencias vendorizadas do pip.
RUN python -m venv --without-pip /app/venv

COPY requirements.txt .
# FALHA 3 (sem verificacao de integridade): cada pacote e conferido contra o
# hash registrado no requirements.txt; um pacote adulterado aborta o build.
RUN pip --python /app/venv/bin/python install --no-cache-dir --require-hashes -r requirements.txt \
    && mkdir -p /app/data

FROM cgr.dev/chainguard/python:latest@sha256:38ba1cbf71702bacc5f5be22ea41e3d4ad1bfb2565413b0caf4bafde38e831f2 AS runtime

WORKDIR /app
ENV PATH="/app/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TASKFLOW_DATABASE=/app/data/taskflow.db

COPY --from=build /app/venv /app/venv
COPY --from=build --chown=65532:65532 /app/data /app/data
COPY app.py gunicorn.conf.py ./
COPY templates ./templates

# FALHA 2 (rodando como root): usuario sem privilegios (nonroot, UID 65532).
USER 65532:65532

# FALHA 4 (segredo em ENV/ARG): nenhum segredo e gravado na imagem.
# TASKFLOW_SECRET_KEY e as senhas iniciais sao injetadas em tempo de execucao
# (veja scripts/docker-run-seguro.sh).

# FALHA 5 (porta do servidor de desenvolvimento): a porta 5000 agora e servida
# pelo gunicorn; EXPOSE apenas documenta a porta.
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/login', timeout=2)"]

# FALHA 6 (debug ligado e servidor de desenvolvimento): gunicorn como servidor
# WSGI de producao; o modo debug do Flask nao e ativado em lugar nenhum.
ENTRYPOINT ["python", "-m", "gunicorn"]
CMD ["--config", "gunicorn.conf.py", "app:app"]
