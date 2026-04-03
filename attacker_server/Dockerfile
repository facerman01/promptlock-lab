# Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Copy server code
COPY server.py .

# Install nothing needed (uses stdlib)

EXPOSE 9001

CMD ["python", "server.py"]