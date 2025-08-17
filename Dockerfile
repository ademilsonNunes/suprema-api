FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Instalar apenas o essencial
RUN apt-get update && apt-get install -y \
    curl \
    redis-server \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Instalar dependências Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código
COPY api ./api
COPY admin_app ./admin_app  
COPY sql ./sql
COPY start.sh .

EXPOSE 8508 8510

CMD ["./start.sh"]
