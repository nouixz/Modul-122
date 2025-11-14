# Dockerfile for tkinter + SQLite app
# Note: Using Debian base with system python3 + python3-tk to ensure Tkinter availability.

FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DB_PATH=/app/data/passwords.db

# Install Python3, Tkinter and minimal tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      python3 \
      python3-pip \
      python3-tk \
      tk \
      ca-certificates \
      && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy app code
COPY . /app

# Ensure data dir exists (mounted as volume at runtime)
RUN mkdir -p /app/data

# No external deps required; keep step for extensibility
RUN python3 -m pip install --no-cache-dir --upgrade pip

# Default: run the GUI app
CMD ["python3", "main.py"]
