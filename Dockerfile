FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY bot ./bot
# База хранится в томе, чтобы не терялась при пересборке
ENV DB_PATH=/data/pdd_bot.db
VOLUME /data
CMD ["python", "-m", "bot"]
