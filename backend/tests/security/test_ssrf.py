"""
/calendar/proxy fetches a URL the user gives it (services/safe_fetch.py). It must never reach the
backend's own network: the cloud metadata service, localhost (the emulator, the app itself), or
private ranges, whether named directly, through DNS, or through a redirect. It also limits what it
returns: iCalendar files only, of a bounded size, fetched within a time limit.

Most tests use `http_mock` and the fake `dns`, which the address check runs against. Those under
"Real connections" use a server on 127.0.0.1, so the connection-time check runs too.
"""

import ipaddress
import re
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import requests

from apps.calendar import api as calendar_api
from services import safe_fetch
from tests.conftest import PUBLIC_TEST_ADDRESS

ICS = b"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n"
FEED_URL = "https://calendar.example.com/feed.ics"
BLOCKED = "Failed to fetch calendar: its address isn't a public one"


@pytest.fixture
def upstream(http_mock):
    """Answers every URL with a calendar and records each request, so a test can see none was sent."""
    http_mock.get(re.compile(r".*"), body=ICS)
    return http_mock


def _proxy(client, url):
    return client.get("/calendar/proxy", url=url)


# --- Addresses that aren't public ---

INTERNAL_URLS = [
    # Cloud metadata services (EC2 and GCP's are both link-local).
    "http://169.254.169.254/latest/meta-data/iam/security-credentials/",
    "http://[fd00:ec2::254]/latest/meta-data/",
    "http://100.100.100.200/latest/meta-data/",  # Alibaba, in the carrier-grade NAT range
    # Loopback, however it's spelled.
    "http://localhost:8080/",  # the Firestore emulator in development
    "http://127.0.0.1:8000/api/auth/me",
    "http://127.1/",
    "http://2130706433/",
    "http://0x7f000001/",
    "http://0.0.0.0:8000/",
    "http://[::1]/",
    "http://[::]/",
    "http://[::ffff:127.0.0.1]/",
    "http://[::ffff:a9fe:a9fe]/",  # 169.254.169.254, IPv4-mapped
    "http://[64:ff9b::a9fe:a9fe]/",  # 169.254.169.254 through NAT64
    "http://[2002:7f00:1::]/",  # 127.0.0.1 through 6to4
    "http://[2001:0:4136:e378:8000:63bf:3fff:fdd2]/",  # Teredo
    # Private, link-local, multicast and reserved ranges.
    "http://10.0.0.5/",
    "http://172.16.0.1/",
    "http://192.168.1.1/",
    "http://169.254.1.1/",
    "http://[fe80::1]/",
    "http://[fc00::1]/",
    "http://224.0.0.1/",
    "http://240.0.0.1/",
    "http://255.255.255.255/",
    "http://192.0.2.1/",
    # Credentials, ports and schemes don't change where it goes.
    "https://user:pass@127.0.0.1/",
    "https://127.0.0.1:443/",
    "http://127.0.0.1:22/",
]


@pytest.mark.parametrize("url", INTERNAL_URLS)
def test_internal_address_is_refused(auth_client, upstream, url):
    response = _proxy(auth_client, url)

    assert response.status_code == 400
    assert response.json() == {"detail": BLOCKED}
    assert len(upstream.calls) == 0


@pytest.mark.parametrize(
    "addresses",
    [["169.254.169.254"], ["10.1.2.3"], ["127.0.0.1"], ["::1"], [PUBLIC_TEST_ADDRESS, "10.0.0.1"]],
    ids=["metadata", "private", "loopback", "loopback-v6", "public-and-private"],
)
def test_name_resolving_to_an_internal_address_is_refused(auth_client, upstream, dns, addresses):
    dns["metadata.google.internal"] = addresses

    response = _proxy(auth_client, "http://metadata.google.internal/computeMetadata/v1/")

    assert response.json() == {"detail": BLOCKED}
    assert len(upstream.calls) == 0


def test_name_that_does_not_resolve(auth_client, upstream, dns, monkeypatch):
    def fail(host, port):
        raise OSError("Name or service not known")

    monkeypatch.setattr(safe_fetch, "resolve", fail)

    response = _proxy(auth_client, FEED_URL)

    assert response.json() == {"detail": "Failed to fetch calendar: its host couldn't be found"}


def test_public_address_is_fetched(auth_client, upstream, dns):
    dns["calendar.example.com"] = [PUBLIC_TEST_ADDRESS, "2606:2800:21f:cb07:6820:80da:af6b:8b2c"]

    response = _proxy(auth_client, FEED_URL)

    assert response.status_code == 200
    assert response.content == ICS


@pytest.mark.parametrize("url", ["file:///etc/passwd", "gopher://127.0.0.1:6379/_INFO", "dict://127.0.0.1:11211/"])
def test_other_schemes_are_422(auth_client, upstream, url):
    response = _proxy(auth_client, url)

    assert response.status_code == 422
    assert len(upstream.calls) == 0


# --- Redirects ---


@pytest.mark.parametrize(
    "location",
    [
        "http://169.254.169.254/latest/meta-data/",
        "http://localhost:8080/",
        "http://[::1]/",
        "http://10.0.0.1/",
        "http://metadata.google.internal/",
    ],
)
def test_redirect_to_an_internal_address_is_refused(auth_client, http_mock, dns, location):
    dns["metadata.google.internal"] = ["169.254.169.254"]
    http_mock.get(FEED_URL, status=302, headers={"Location": location})
    internal = http_mock.get(re.compile(r"http://(?!calendar\.example\.com).*"), body=ICS)

    response = _proxy(auth_client, FEED_URL)

    assert response.json() == {"detail": BLOCKED}
    assert internal.call_count == 0


@pytest.mark.parametrize("location", ["file:///etc/passwd", "gopher://127.0.0.1:6379/_INFO", "ftp://example.com/"])
def test_redirect_to_another_scheme_is_refused(auth_client, http_mock, location):
    http_mock.get(FEED_URL, status=301, headers={"Location": location})

    response = _proxy(auth_client, FEED_URL)

    assert response.status_code == 400
    assert response.json()["detail"].startswith("Failed to fetch calendar")
    assert len(http_mock.calls) == 1


def test_redirects_between_public_hosts_are_followed(auth_client, http_mock):
    http_mock.get(FEED_URL, status=301, headers={"Location": "https://cdn.example.net/a/feed.ics"})
    http_mock.get("https://cdn.example.net/a/feed.ics", status=307, headers={"Location": "../b/feed.ics"})
    http_mock.get("https://cdn.example.net/b/feed.ics", body=ICS)

    response = _proxy(auth_client, FEED_URL)

    assert response.status_code == 200
    assert response.content == ICS


def test_too_many_redirects(auth_client, http_mock):
    for hop in range(safe_fetch.MAX_REDIRECTS + 1):
        http_mock.get(f"https://calendar.example.com/{hop}", status=302, headers={"Location": f"/{hop + 1}"})

    response = _proxy(auth_client, "https://calendar.example.com/0")

    assert response.json() == {"detail": "Failed to fetch calendar: it redirects too many times"}
    assert len(http_mock.calls) == safe_fetch.MAX_REDIRECTS + 1


# --- What it returns ---


@pytest.mark.parametrize(
    "body",
    [
        b"<!doctype html><html><script>alert(1)</script></html>",
        b'{"AccessKeyId": "AKIA..."}',
        b"",
        b"BEGIN:VCARD\r\nEND:VCARD\r\n",
        b"\x89PNG\r\n\x1a\n",
    ],
    ids=["html", "json", "empty", "vcard", "binary"],
)
def test_anything_but_an_icalendar_file_is_refused(auth_client, http_mock, body):
    http_mock.get(FEED_URL, body=body, content_type="text/calendar")

    response = _proxy(auth_client, FEED_URL)

    assert response.json() == {"detail": "Failed to fetch calendar: it isn't an iCalendar file"}


@pytest.mark.parametrize(
    "body", [ICS, b"\xef\xbb\xbf" + ICS, b"\r\n  " + ICS, ICS.lower()], ids=["plain", "bom", "whitespace", "lowercase"]
)
def test_icalendar_files_are_returned_unchanged(auth_client, http_mock, body):
    http_mock.get(FEED_URL, body=body, content_type="application/octet-stream")

    response = _proxy(auth_client, FEED_URL)

    assert response.status_code == 200
    assert response.content == body


def test_response_headers(auth_client, http_mock):
    http_mock.get(FEED_URL, body=ICS, headers={"Set-Cookie": "session=upstream", "Access-Control-Allow-Origin": "*"})

    response = _proxy(auth_client, FEED_URL)

    assert response["Content-Type"] == "text/calendar"
    assert response["X-Content-Type-Options"] == "nosniff"
    assert response["Cache-Control"] == "no-store"
    assert "Set-Cookie" not in response
    assert "Access-Control-Allow-Origin" not in response


@pytest.fixture
def small_limit(monkeypatch):
    monkeypatch.setattr(calendar_api, "MAX_CALENDAR_BYTES", 1024)
    return 1024


def test_declared_size_over_the_limit_is_refused(auth_client, http_mock, small_limit):
    http_mock.get(
        FEED_URL, body=ICS, headers={"Content-Length": str(small_limit + 1)}, auto_calculate_content_length=False
    )

    assert _proxy(auth_client, FEED_URL).json() == {"detail": "Failed to fetch calendar: it's larger than 1,024 bytes"}


def test_body_over_the_limit_is_refused(auth_client, http_mock, small_limit):
    http_mock.get(FEED_URL, body=ICS + b"X" * small_limit)

    assert _proxy(auth_client, FEED_URL).json() == {"detail": "Failed to fetch calendar: it's larger than 1,024 bytes"}


def test_body_at_the_limit_is_returned(auth_client, http_mock, small_limit):
    body = ICS + b"X" * (small_limit - len(ICS))
    http_mock.get(FEED_URL, body=body)

    assert _proxy(auth_client, FEED_URL).content == body


def test_the_real_limit_is_10_mb():
    assert calendar_api.MAX_CALENDAR_BYTES == 10 * 2**20


@pytest.mark.parametrize(
    "failure, reason",
    [
        ({"status": 404}, "the server answered 404"),
        ({"status": 500}, "the server answered 500"),
        ({"body": requests.ConnectionError("[Errno 111] Connection refused to 10.0.0.1:22")}, "couldn't be reached"),
        ({"body": requests.ReadTimeout("read timed out (10.0.0.1)")}, "took too long"),
    ],
    ids=["404", "500", "refused", "timeout"],
)
def test_errors_say_what_failed_without_network_details(auth_client, http_mock, failure, reason):
    http_mock.get(FEED_URL, **failure)

    detail = _proxy(auth_client, FEED_URL).json()["detail"]

    assert detail.startswith("Failed to fetch calendar: ")
    assert reason in detail
    assert "10.0.0.1" not in detail
    assert "Errno" not in detail


# --- Real connections ---


class _Server:
    """An HTTP server on 127.0.0.1 with a few routes; `requests` lists the paths it was asked for."""

    def __init__(self):
        self.requests: list[str] = []
        server = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                server.requests.append(self.path)
                if self.path.startswith("/redirect?to="):
                    self.send_response(302)
                    self.send_header("Location", self.path.removeprefix("/redirect?to="))
                    self.end_headers()
                elif self.path == "/slow":
                    self.send_response(200)
                    self.end_headers()
                    try:
                        self.wfile.write(ICS)
                        for _ in range(100):  # a byte every 50 ms, for 5 s
                            self.wfile.write(b"X")
                            self.wfile.flush()
                            time.sleep(0.05)
                    except OSError:
                        pass
                elif self.path == "/stall":  # starts the body, then stops sending
                    self.send_response(200)
                    self.send_header("Content-Length", "1000")
                    self.end_headers()
                    try:
                        self.wfile.write(ICS[:15])
                        self.wfile.flush()
                        time.sleep(3)
                    except OSError:
                        pass
                elif self.path == "/truncated":  # closes the connection partway through the body
                    self.send_response(200)
                    self.send_header("Content-Length", "1000")
                    self.end_headers()
                    self.wfile.write(ICS[:15])
                elif self.path == "/bad-gzip":  # says it's gzipped, but isn't
                    self.send_response(200)
                    self.send_header("Content-Encoding", "gzip")
                    self.send_header("Content-Length", str(len(ICS)))
                    self.end_headers()
                    self.wfile.write(ICS)
                else:
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(ICS)))
                    self.end_headers()
                    self.wfile.write(ICS)

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.httpd.daemon_threads = True
        self.port = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True).start()

    def url(self, path="/feed.ics", host="127.0.0.1"):
        return f"http://{host}:{self.port}{path}"


@pytest.fixture
def server():
    s = _Server()
    yield s
    s.httpd.shutdown()
    s.httpd.server_close()


def test_real_loopback_server_is_not_contacted(auth_client, server):
    response = _proxy(auth_client, server.url())

    assert response.json() == {"detail": BLOCKED}
    assert server.requests == []


def test_allowed_private_host_is_fetched(settings, auth_client, server):
    """SAFE_FETCH_PRIVATE_HOSTS (the E2E stack's stub) is the only way past the check."""
    settings.SAFE_FETCH_PRIVATE_HOSTS = ["127.0.0.1"]

    response = _proxy(auth_client, server.url())

    assert response.status_code == 200
    assert response.content == ICS
    assert server.requests == ["/feed.ics"]


def test_real_redirect_from_an_allowed_host_to_another_is_refused(settings, auth_client, server):
    settings.SAFE_FETCH_PRIVATE_HOSTS = ["localhost"]

    response = _proxy(auth_client, server.url(f"/redirect?to={server.url()}", host="localhost"))

    assert response.json() == {"detail": BLOCKED}
    assert server.requests == [f"/redirect?to={server.url()}"]


@pytest.mark.parametrize("scheme", ["http", "https"])
def test_dns_rebinding_is_caught_when_connecting(auth_client, server, monkeypatch, scheme):
    """The name passes the check as a public address, then resolves to loopback for the connection."""
    answers = iter([PUBLIC_TEST_ADDRESS, "127.0.0.1"])
    monkeypatch.setattr(safe_fetch, "resolve", lambda host, port: [ipaddress.ip_address(next(answers))])

    response = _proxy(auth_client, server.url(host="rebind.invalid").replace("http:", f"{scheme}:"))

    assert response.json() == {"detail": BLOCKED}
    assert server.requests == []


def test_connection_goes_to_the_checked_address(settings, auth_client, server, dns):
    """The fake DNS's answer is used to connect: `.invalid` names never resolve for real."""
    dns["feed.invalid"] = ["127.0.0.1"]
    settings.SAFE_FETCH_PRIVATE_HOSTS = ["feed.invalid"]

    response = _proxy(auth_client, server.url(host="feed.invalid"))

    assert response.status_code == 200
    assert server.requests == ["/feed.ics"]


def test_proxy_settings_in_the_environment_are_ignored(settings, auth_client, server, monkeypatch):
    proxy = _Server()
    try:
        for var in ("HTTP_PROXY", "http_proxy", "HTTPS_PROXY", "ALL_PROXY"):
            monkeypatch.setenv(var, proxy.url("/"))
        monkeypatch.delenv("NO_PROXY", raising=False)
        monkeypatch.delenv("no_proxy", raising=False)
        settings.SAFE_FETCH_PRIVATE_HOSTS = ["localhost"]

        response = _proxy(auth_client, server.url(host="localhost"))

        assert response.status_code == 200
        assert proxy.requests == []
    finally:
        proxy.httpd.shutdown()
        proxy.httpd.server_close()


def test_slow_server_is_cut_off_at_the_deadline(settings, auth_client, server, monkeypatch):
    settings.SAFE_FETCH_PRIVATE_HOSTS = ["127.0.0.1"]
    monkeypatch.setattr(safe_fetch, "DEADLINE", 1)
    started = time.monotonic()

    response = _proxy(auth_client, server.url("/slow"))

    assert response.json() == {"detail": "Failed to fetch calendar: the server took too long"}
    assert time.monotonic() - started < 3


def test_each_checked_address_is_tried_in_turn(settings, auth_client, server, dns):
    """Like urllib3: if the first address doesn't answer (nothing listens on ::1 here), the next is used."""
    dns["dual-stack.invalid"] = ["::1", "127.0.0.1"]
    settings.SAFE_FETCH_PRIVATE_HOSTS = ["dual-stack.invalid"]

    response = _proxy(auth_client, server.url(host="dual-stack.invalid"))

    assert response.status_code == 200
    assert server.requests == ["/feed.ics"]


def test_no_checked_address_answers(settings, auth_client, dns):
    dns["down.invalid"] = ["::1", "127.0.0.1"]
    settings.SAFE_FETCH_PRIVATE_HOSTS = ["down.invalid"]
    with socket.socket() as unused:  # a port nothing listens on
        unused.bind(("127.0.0.1", 0))
        port = unused.getsockname()[1]

    response = _proxy(auth_client, f"http://down.invalid:{port}/feed.ics")

    assert response.json() == {"detail": "Failed to fetch calendar: the server couldn't be reached"}


@pytest.mark.parametrize(
    "path, reason",
    [
        ("/stall", "the server took too long"),
        ("/truncated", "the server's response couldn't be read"),
        ("/bad-gzip", "the server's response couldn't be read"),
    ],
    ids=["stalled-body", "truncated-body", "bad-gzip"],
)
def test_body_that_fails_to_read_is_400(settings, auth_client, server, monkeypatch, path, reason):
    """urllib3 raises its own errors (ReadTimeoutError, ProtocolError, DecodeError) while the body is read."""
    settings.SAFE_FETCH_PRIVATE_HOSTS = ["127.0.0.1"]
    monkeypatch.setattr(safe_fetch, "TIMEOUT", 0.5)

    response = _proxy(auth_client, server.url(path))

    assert response.status_code == 400
    assert response.json() == {"detail": f"Failed to fetch calendar: {reason}"}
    assert b"VCALENDAR" not in response.content
    assert server.requests == [path]
