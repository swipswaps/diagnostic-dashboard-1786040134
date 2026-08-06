FROM python:3.11-slim
RUN apt-get update && apt-get install -y sqlite3 curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
COPY templates/ templates/
COPY static/ static/
ENV DB_PATH=/data/diagnostics.db
VOLUME ["/data"]
CMD ["python3", "-u", "app.py"]
