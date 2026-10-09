FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NAS_TODO_DB=/data/todo.sqlite \
    NAS_TODO_PORT=8787

WORKDIR /app
RUN groupadd --gid 1000 todo && useradd --uid 1000 --gid 1000 --no-create-home todo \
    && mkdir /data && chown todo:todo /data
COPY --chown=todo:todo app.py /app/app.py
USER 1000:1000
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8787/health', timeout=3)" || exit 1
CMD ["python", "/app/app.py"]
