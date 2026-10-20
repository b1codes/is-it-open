"""
Fetches URLs that users supply (the iCal proxy) without letting them reach the backend's own network.

A URL's host must resolve only to public addresses, so the cloud metadata service (169.254.169.254),
localhost, the Firestore emulator and anything else on a private network are refused, however the
address is spelled. The check runs for the URL and again for each redirect before it's followed. The
connection then goes to the address that passed, so a DNS answer that changes between the check and
the request (rebinding) doesn't get through either. Proxy settings from the environment are ignored,
since a proxy would make the connection on our behalf.

Responses are read up to a size limit and within a total time limit.

Hosts in settings.SAFE_FETCH_PRIVATE_HOSTS may resolve to private addresses. Only the E2E stack sets
it, for its stub server.
"""

import ipaddress
import socket
import time
from collections.abc import Callable
from urllib.parse import urljoin

import requests
from django.conf import settings
from requests.adapters import HTTPAdapter
from urllib3.connection import HTTPConnection, HTTPSConnection
from urllib3.connectionpool import HTTPConnectionPool, HTTPSConnectionPool
from urllib3.exceptions import ConnectTimeoutError
from urllib3.util import parse_url

IPAddress = ipaddress.IPv4Address | ipaddress.IPv6Address

MAX_REDIRECTS = 5
# Seconds allowed to connect, and between bytes once connected.
TIMEOUT = 10
# Seconds allowed for the whole fetch, redirects included.
DEADLINE = 30
_CHUNK_SIZE = 64 * 1024

_NAT64 = ipaddress.ip_network("64:ff9b::/96")


class FetchError(Exception):
    """The URL couldn't be fetched. The message says why, without details of the network."""


class BlockedAddress(FetchError):
    """The URL's host resolves to an address that isn't public."""


def resolve(host: str, port: int) -> list[IPAddress]:
    """The addresses `host` resolves to (an IP literal resolves to itself)."""
    infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    return [ipaddress.ip_address(str(info[4][0]).split("%")[0]) for info in infos]


def is_public(address: IPAddress) -> bool:
    """Whether `address`, and any IPv4 address embedded in it, is a publicly routable unicast address."""
    addresses: list[IPAddress] = [address]
    if isinstance(address, ipaddress.IPv6Address):
        if address.ipv4_mapped:
            addresses.append(address.ipv4_mapped)
        if address.sixtofour:
            addresses.append(address.sixtofour)
        if address.teredo:
            addresses.extend(address.teredo)
        if address in _NAT64:
            addresses.append(ipaddress.IPv4Address(int(address) & 0xFFFFFFFF))
    return all(a.is_global and not a.is_multicast for a in addresses)


def check_host(host: str, port: int) -> list[IPAddress]:
    """The addresses to connect to for `host`. Raises BlockedAddress if any of them isn't public."""
    host = host.strip("[]")
    try:
        addresses = list(dict.fromkeys(resolve(host, port)))
    except (OSError, UnicodeError, ValueError) as e:
        raise FetchError("its host couldn't be found") from e
    if host not in settings.SAFE_FETCH_PRIVATE_HOSTS and not all(is_public(a) for a in addresses):
        raise BlockedAddress("its address isn't a public one")
    return addresses


# --- Connections that go to the checked addresses ---


def _connect_to_checked_address(connection: HTTPConnection, connect: Callable[[], socket.socket]) -> socket.socket:
    """Connects to the first of the host's checked addresses that answers, as urllib3 itself would."""
    host = connection._dns_host
    error: Exception | None = None
    try:
        for address in check_host(host, connection.port):
            connection._dns_host = str(address)
            try:
                return connect()  # TLS still checks the certificate against `connection.host`
            except ConnectTimeoutError as e:  # NewConnectionError is one too
                error = e
    finally:
        connection._dns_host = host
    raise error or FetchError("its host couldn't be found")


class _CheckedHTTPConnection(HTTPConnection):
    def _new_conn(self) -> socket.socket:
        return _connect_to_checked_address(self, super()._new_conn)


class _CheckedHTTPSConnection(HTTPSConnection):
    def _new_conn(self) -> socket.socket:
        return _connect_to_checked_address(self, super()._new_conn)


class _CheckedHTTPConnectionPool(HTTPConnectionPool):
    ConnectionCls = _CheckedHTTPConnection


class _CheckedHTTPSConnectionPool(HTTPSConnectionPool):
    ConnectionCls = _CheckedHTTPSConnection


class _CheckedAdapter(HTTPAdapter):
    def init_poolmanager(self, *args, **kwargs):
        super().init_poolmanager(*args, **kwargs)
        self.poolmanager.pool_classes_by_scheme = {
            "http": _CheckedHTTPConnectionPool,
            "https": _CheckedHTTPSConnectionPool,
        }


# --- Fetching ---


def _session() -> requests.Session:
    session = requests.Session()
    session.trust_env = False  # no proxies or .netrc credentials from the environment
    session.mount("http://", _CheckedAdapter())
    session.mount("https://", _CheckedAdapter())
    return session


def _remaining(deadline: float) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise FetchError("the server took too long")
    return min(TIMEOUT, remaining)


def _read(response: requests.Response, max_bytes: int, deadline: float) -> bytes:
    too_large = FetchError(f"it's larger than {max_bytes:,} bytes")
    length = response.headers.get("Content-Length", "")
    if length.isdigit() and int(length) > max_bytes:
        raise too_large
    body = bytearray()
    # read1 returns after each receive, so a server sending a byte at a time still meets the deadline
    # (overshooting it by at most TIMEOUT). Chunks are decompressed, so a gzip bomb is caught too.
    while chunk := response.raw.read1(_CHUNK_SIZE, decode_content=True):
        body += chunk
        if len(body) > max_bytes:
            raise too_large
        _remaining(deadline)
    return bytes(body)


def fetch(url: str, *, max_bytes: int) -> bytes:
    """GET `url` and return its body. Raises FetchError, with a reason to show the user, if it can't."""
    deadline = time.monotonic() + DEADLINE
    with _session() as session:
        try:
            for _ in range(MAX_REDIRECTS + 1):
                request = session.prepare_request(requests.Request("GET", url))
                parsed = parse_url(request.url or "")
                if parsed.scheme not in ("http", "https") or not parsed.host:
                    raise FetchError("it isn't an http or https URL")
                check_host(parsed.host, parsed.port or (443 if parsed.scheme == "https" else 80))

                timeout = _remaining(deadline)
                with session.send(request, allow_redirects=False, stream=True, timeout=timeout) as response:
                    if response.is_redirect:
                        url = urljoin(request.url or "", response.headers["Location"])
                        continue
                    if not response.ok:
                        raise FetchError(f"the server answered {response.status_code}")
                    return _read(response, max_bytes, deadline)
            raise FetchError("it redirects too many times")
        except requests.Timeout as e:
            raise FetchError("the server took too long") from e
        except requests.RequestException as e:
            raise FetchError("the server couldn't be reached") from e
