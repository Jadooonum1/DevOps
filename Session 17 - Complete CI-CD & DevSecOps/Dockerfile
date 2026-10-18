# syntax=docker/dockerfile:1
# ---- build stage: install dependencies into an isolated virtualenv ----
FROM python:3.13-slim AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
COPY requirements.txt /tmp/requirements.txt
# every transitive dependency is pinned in requirements.txt, so --no-deps keeps the set exact
RUN /opt/venv/bin/pip install --no-deps -r /tmp/requirements.txt \
 && /opt/venv/bin/pip uninstall -y pip

# ---- runtime stage: no compiler, no pip, non-root, read-only friendly ----
FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/opt/venv/bin:$PATH \
    LOAN_DB_PATH=/data/loans.db

# patch OS packages, then drop pip/setuptools from the base interpreter (not needed at runtime)
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/* \
 && (python -m pip uninstall -y pip setuptools wheel || true) \
 && groupadd --gid 10001 library \
 && useradd --uid 10001 --gid library --no-create-home --shell /usr/sbin/nologin librarian \
 && mkdir /data && chown librarian:library /data

COPY --from=build /opt/venv /opt/venv
WORKDIR /app
COPY --chown=root:root loan_service/ ./loan_service/

USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD ["python", "-c", "import urllib.request,sys; sys.exit(urllib.request.urlopen('http://127.0.0.1:8080/healthz').status != 200)"]
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--worker-tmp-dir", "/dev/shm", "loan_service.wsgi:app"]
