FROM python:3.12-slim
RUN pip install --no-cache-dir "psycopg[binary]>=3.1"
WORKDIR /app
COPY respaldar.py restaurar.py ./
ENV BACKUP_DIR=/backups INTERVALO_HORAS=24 RETENCION_DIAS=14
VOLUME /backups
CMD ["python3", "respaldar.py"]
