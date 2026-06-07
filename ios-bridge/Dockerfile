FROM python:3.12-slim

RUN apt-get update && apt-get install -y ffmpeg curl && rm -rf /var/lib/apt/lists/*

# Install yt-dlp pinned version via pip — kept current; YouTube changes its
# player/signature internals often enough that a stale yt-dlp is the #1 cause
# of "Unable to find stream URL" extraction failures.
RUN pip install --no-cache-dir yt-dlp==2026.3.17

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PYTHONUNBUFFERED=1

EXPOSE 8002

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8002"]
