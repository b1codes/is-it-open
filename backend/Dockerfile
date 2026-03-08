# backend/Dockerfile
FROM python:3.11-slim

# Install system libs for PostGIS
RUN apt-get update && apt-get install -y \
    binutils libproj-dev gdal-bin curl \
    && rm -rf /var/lib/apt/lists/*

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
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project --no-dev

# Copy project code
COPY . .

# Run collectstatic for production (Whitenoise will serve these)
# We set a dummy SECRET_KEY and DATABASE_URL for the build step
RUN SECRET_KEY=build-time-only DATABASE_URL=sqlite:///db.sqlite3 python manage.py collectstatic --noinput

EXPOSE 8000

# Use gunicorn with uvicorn workers for ASGI support
CMD ["gunicorn", "config.asgi:application", "-k", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000", "--workers", "4", "--access-log", "-"]
