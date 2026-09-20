FROM python:3.12-slim
WORKDIR /app
COPY relay/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt && useradd -u 10001 -m macbridge && mkdir /data && chown macbridge /data
COPY contracts /app/contracts
COPY relay /app/relay
COPY web /app/web
USER macbridge
ENV DATABASE_PATH=/data/macbridge.sqlite3
EXPOSE 8080
CMD ["uvicorn", "relay.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080", "--workers", "1", "--no-access-log", "--ws-max-size", "65536"]
