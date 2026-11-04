"""Property-based tests for document-ID encoding and the place-name search index."""

from urllib.parse import unquote

from hypothesis import assume, given
from hypothesis import strategies as st

from apps.places.repository import _MAX_SEARCH_TERM_LENGTH, _normalize_text, _search_terms, _words
from services.firestore import _HASHED_PREFIX, _MAX_DOC_ID_BYTES, _RESERVED_DOC_ID, doc_id

# Keys look like TomTom IDs, Auth0 subs, or usernames, but any non-empty text must work.
keys = st.text(min_size=1, max_size=60) | st.text(min_size=1500, max_size=1600) | st.sampled_from([".", "..", "__x__"])


@given(keys)
def test_doc_id_is_always_a_valid_firestore_id(key):
    encoded = doc_id(key)

    assert encoded
    assert "/" not in encoded
    assert len(encoded.encode("utf-8")) <= _MAX_DOC_ID_BYTES
    assert encoded not in (".", "..")
    assert not _RESERVED_DOC_ID.fullmatch(encoded)


@given(keys)
def test_doc_id_is_reversible_unless_hashed(key):
    encoded = doc_id(key)

    if encoded.startswith(_HASHED_PREFIX):
        assert len(key) > 100  # only overlong keys are hashed
    else:
        assert unquote(encoded) == key


@given(keys, keys)
def test_distinct_keys_get_distinct_ids(a, b):
    assume(a != b)

    assert doc_id(a) != doc_id(b)


@given(keys)
def test_doc_id_is_deterministic(key):
    assert doc_id(key) == doc_id(key)


# Place names: words with punctuation, mixed case, and odd whitespace.
names = st.text(
    st.characters(categories=["L", "N", "P", "Zs"]) | st.sampled_from(["\t", "\n", "&", "'", "-"]), max_size=60
)


@given(names, st.data())
def test_every_substring_query_finds_the_name(name, data):
    """search_places' candidate query (its longest word, truncated) is indexed for every matching name."""
    normalized = _normalize_text(name)
    assume(normalized.strip())
    start = data.draw(st.integers(0, len(normalized) - 1))
    end = data.draw(st.integers(start + 1, len(normalized)))
    query = normalized[start:end]
    assume(_words(query))

    term = max(_words(query), key=len)[:_MAX_SEARCH_TERM_LENGTH]

    assert term in _search_terms(name)
    assert _normalize_text(query) in normalized  # and the in-memory check matches it


@given(names)
def test_search_terms_are_bounded_lowercase_substrings_of_words(name):
    words = _words(name)

    for term in _search_terms(name):
        assert 1 <= len(term) <= _MAX_SEARCH_TERM_LENGTH
        assert term == term.casefold()
        assert any(term in word for word in words)
