# e2e/stub/Dockerfile
# The E2E stack's stand-in for TomTom, an iCal host and map tiles (see server.py).
FROM python:3.11-slim

WORKDIR /stub
COPY server.py .

EXPOSE 8090

HEALTHCHECK --interval=2s --timeout=2s --retries=15 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8090/health')" || exit 1

CMD ["python", "server.py"]
