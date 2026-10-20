"""
GET /health: a liveness check for Docker's healthcheck, load balancers and the post-deploy smoke
test (smoke/).

It answers before Django validates the Host header against ALLOWED_HOSTS, since probes address the
container by IP or as localhost. It doesn't touch Firestore either: a slow database shouldn't get a
healthy container restarted. The smoke test checks Firestore through the API.
"""

from django.http import JsonResponse

HEALTH_PATH = "/health"


class HealthCheckMiddleware:
    """Answers GET and HEAD /health. Runs first in MIDDLEWARE, before anything reads the host."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.path == HEALTH_PATH and request.method in ("GET", "HEAD"):
            return JsonResponse({"status": "ok"})
        return self.get_response(request)
