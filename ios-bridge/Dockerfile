FROM python:3.12-slim

# atomicparsley is required for yt-dlp's --embed-thumbnail to work on M4A —
# ffmpeg alone can embed thumbnails into mp3/opus/etc, but not M4A/MP4 containers.
# aria2 (aria2c) is used as yt-dlp's external downloader for multi-connection,
# segmented downloads — substantially faster than the built-in downloader.
RUN apt-get update && apt-get install -y ffmpeg curl unzip atomicparsley aria2 && rm -rf /var/lib/apt/lists/*

# yt-dlp now needs a JS runtime to solve YouTube's player/signature challenge
# (EJS) — without one, extraction fails for most videos with "This video is
# not available". Deno is the runtime yt-dlp enables by default.
RUN curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh
ENV PATH="/usr/local/bin:${PATH}"

# Install yt-dlp pinned version via pip — kept current; YouTube changes its
# player/signature internals often enough that a stale yt-dlp is the #1 cause
# of "Unable to find stream URL" extraction failures.
# yt-dlp-ejs bundles the JS challenge solver script yt-dlp now requires for
# YouTube extraction, so Deno can run it without fetching remote components.
RUN pip install --no-cache-dir yt-dlp==2026.6.9 yt-dlp-ejs

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PYTHONUNBUFFERED=1

EXPOSE 8002

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8002"]
