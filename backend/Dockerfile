# backend/Dockerfile
FROM python:3.11-slim

RUN apt-get update && apt-get install -y curl \
    && rm -rf /var/lib/apt/lists/*

# The app runs from the uv-managed venv below, so the base image's own setuptools and wheel are
# never used; removing them keeps their (and their vendored packages') CVEs out of the image scan.
RUN pip uninstall -y setuptools wheel

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /code

# Enable bytecode compilation
ENV UV_COMPILE_BYTECODE=1

# Copy from the cache instead of linking since it's a separate volume
ENV UV_LINK_MODE=copy

# Place the virtual environment outside of the code mount
ENV UV_PROJECT_ENVIRONMENT=/opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install dependencies
# Note: we copy pyproject.toml and uv.lock first for caching
# INSTALL_DEV=true adds the test/lint tooling (docker-compose.yml sets it for local dev and CI).
ARG INSTALL_DEV=false
COPY pyproject.toml uv.lock ./
RUN if [ "$INSTALL_DEV" = "true" ]; then \
        uv sync --frozen --no-install-project; \
    else \
        uv sync --frozen --no-install-project --no-dev; \
    fi

# Copy project code
COPY . .

# Run collectstatic for production (Whitenoise will serve these)
# We set a dummy SECRET_KEY for the build step
RUN SECRET_KEY=build-time-only python manage.py collectstatic --noinput

EXPOSE 8000

# Use gunicorn with uvicorn workers for ASGI support
CMD ["gunicorn", "config.asgi:application", "-k", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000", "--workers", "4", "--access-logfile", "-"]
