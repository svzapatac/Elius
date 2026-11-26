FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends age tzdata && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir "psycopg[binary]>=3.1"
WORKDIR /app
COPY respaldar.py restaurar.py ./
ENV BACKUP_DIR=/backups HORA_DIARIA=02:00 TZ=America/Bogota RETENCION_DIAS=30
VOLUME /backups
CMD ["python3", "respaldar.py"]
