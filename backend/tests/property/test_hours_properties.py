"""Property-based tests for opening-hours parsing (TomTom) and normalization (repository)."""

import datetime
import re

from hypothesis import given
from hypothesis import strategies as st

from apps.places.api import PlaceCreateSchema
from apps.places.repository import _normalize_hours
from services.tomtom import TomTomClient

parse_hours = TomTomClient()._parse_opening_hours
parse_results = TomTomClient()._parse_results

HH_MM = re.compile(r"\d\d:\d\d")

json_values = st.recursive(
    st.none() | st.booleans() | st.integers() | st.floats() | st.text(max_size=12),
    lambda children: st.lists(children, max_size=4) | st.dictionaries(st.text(max_size=10), children, max_size=4),
    max_leaves=20,
)


def maybe(strategy):
    """The value, null, or (via `optional_keys`) missing: the ways TomTom fields turn up."""
    return st.none() | strategy


dates = st.dates(min_value=datetime.date(2000, 1, 1), max_value=datetime.date(2100, 12, 31))
iso_dates = dates.map(datetime.date.isoformat)


def times(date_strategy=iso_dates):
    return st.fixed_dictionaries(
        {"date": date_strategy},
        optional={"hour": st.integers(0, 23), "minute": st.integers(0, 59)},
    )


# Ranges as TomTom sends them, with any part possibly malformed.
messy_time = st.fixed_dictionaries(
    {}, optional={"date": maybe(iso_dates | st.text(max_size=12)), "hour": json_values, "minute": json_values}
)
messy_range = (
    st.fixed_dictionaries({}, optional={"startTime": maybe(messy_time), "endTime": maybe(messy_time)}) | json_values
)
messy_hours = st.fixed_dictionaries(
    {}, optional={"mode": st.text(max_size=5), "timeRanges": maybe(st.lists(messy_range))}
)


@given(st.one_of(messy_hours, json_values))
def test_parsing_never_raises_and_output_is_well_formed(data):
    hours = parse_hours(data)

    blocks = [(h["day_of_week"], h["open_time"], h["close_time"]) for h in hours]
    assert len(blocks) == len(set(blocks))
    for h in hours:
        assert set(h) == {"day_of_week", "open_time", "close_time"}
        assert 0 <= h["day_of_week"] <= 6
        assert isinstance(h["open_time"], str) and isinstance(h["close_time"], str)


def _opens_at(time: dict) -> datetime.datetime:
    return datetime.datetime.fromisoformat(time["date"]).replace(hour=time.get("hour", 0), minute=time.get("minute", 0))


def _time_at(moment: datetime.datetime) -> dict:
    return {"date": moment.date().isoformat(), "hour": moment.hour, "minute": moment.minute}


@st.composite
def ranges_of_up_to_a_day(draw):
    """A well-formed range that closes at most a day after it opens (or, malformed, before it)."""
    start = draw(times())
    closes = _opens_at(start) + datetime.timedelta(minutes=draw(st.integers(-7 * 24 * 60, 24 * 60)))
    return {"startTime": start, "endTime": _time_at(closes)}


@given(st.lists(ranges_of_up_to_a_day(), max_size=14))
def test_well_formed_ranges_keep_every_range_on_the_first_date_of_each_weekday(ranges):
    hours = parse_hours({"timeRanges": ranges})

    first_date = {}
    expected = []
    for r in ranges:
        start, end = r["startTime"], r["endTime"]
        day = datetime.date.fromisoformat(start["date"]).weekday()
        if first_date.setdefault(day, start["date"]) != start["date"]:
            continue
        block = {
            "day_of_week": day,
            "open_time": f"{start.get('hour', 0):02d}:{start.get('minute', 0):02d}",
            "close_time": f"{end.get('hour', 0):02d}:{end.get('minute', 0):02d}",
        }
        if block not in expected:
            expected.append(block)
    assert hours == expected
    assert all(HH_MM.fullmatch(h["open_time"]) and HH_MM.fullmatch(h["close_time"]) for h in hours)


WEEK = 7 * 24 * 60


def _week_minutes(start: int, end: int) -> set[int]:
    """The minutes of the week (0 is Monday 00:00) from `start` to `end`, wrapping around."""
    return {minute % WEEK for minute in range(start, end)}


@given(times(), st.integers(24 * 60 + 1, 9 * 24 * 60))
def test_a_range_longer_than_a_day_is_open_for_exactly_its_minutes_of_the_week(start, length):
    opens = _opens_at(start)
    hours = parse_hours(
        {"timeRanges": [{"startTime": start, "endTime": _time_at(opens + datetime.timedelta(minutes=length))}]}
    )

    def minutes(hh_mm):
        return int(hh_mm[:2]) * 60 + int(hh_mm[3:])

    open_minutes: set[int] = set()
    for h in hours:
        # As the app reads a block: one that closes at or before it opens runs past midnight.
        day_start = h["day_of_week"] * 24 * 60 + minutes(h["open_time"])
        block_length = (minutes(h["close_time"]) - minutes(h["open_time"])) % (24 * 60) or 24 * 60
        open_minutes |= _week_minutes(day_start, day_start + block_length)
    # Only the first date of each weekday counts, so a range of over a week stops a week after its first day began.
    first_minute = opens.weekday() * 24 * 60 + opens.hour * 60 + opens.minute
    end = min(length, WEEK - opens.hour * 60 - opens.minute)
    assert open_minutes == _week_minutes(first_minute, first_minute + end)


# TomTom search results with every field possibly missing or null.
coordinates = st.floats(-90, 90) | st.integers(-90, 90)
tomtom_results = st.fixed_dictionaries(
    {},
    optional={
        "id": maybe(st.text(max_size=20)),
        "poi": maybe(
            st.fixed_dictionaries(
                {},
                optional={
                    "name": maybe(st.text(max_size=20)),
                    "phone": maybe(st.text(max_size=10)),
                    "url": maybe(st.text(max_size=10)),
                    "categorySet": maybe(st.lists(maybe(st.fixed_dictionaries({}, optional={"id": st.integers()})))),
                    "categories": maybe(st.lists(maybe(st.text(max_size=10)))),
                    "classifications": maybe(
                        st.lists(
                            maybe(
                                st.fixed_dictionaries(
                                    {},
                                    optional={
                                        "names": maybe(
                                            st.lists(
                                                maybe(st.fixed_dictionaries({}, optional={"name": maybe(st.text())}))
                                            )
                                        )
                                    },
                                )
                            )
                        )
                    ),
                    "openingHours": maybe(messy_hours),
                },
            )
        ),
        "address": maybe(
            st.fixed_dictionaries(
                {},
                optional={
                    "freeformAddress": maybe(st.text(max_size=20)),
                    "streetNumber": st.text(max_size=5),
                    "streetName": st.text(max_size=10),
                    "municipality": st.text(max_size=10),
                },
            )
        ),
        "position": maybe(st.fixed_dictionaries({}, optional={"lat": maybe(coordinates), "lon": maybe(coordinates)})),
    },
)


@given(st.lists(tomtom_results, max_size=5))
def test_every_parsed_result_is_a_valid_place(results):
    parsed = parse_results(results)

    for place in parsed:
        PlaceCreateSchema.model_validate(place)  # what /places/search and details responses require
        assert place["tomtom_id"] and place["name"]
    assert len(parsed) <= len(results)


stored_times = st.from_regex(r"\d\d:\d\d(:\d\d)?", fullmatch=True)
stored_hours = st.lists(
    st.fixed_dictionaries({"day_of_week": st.integers(0, 6), "open_time": stored_times, "close_time": stored_times})
)


@given(stored_hours)
def test_normalized_hours_are_sorted_trimmed_and_stable(hours):
    normalized = _normalize_hours(hours)

    assert len(normalized) == len(hours)
    assert normalized == sorted(normalized, key=lambda h: (h["day_of_week"], h["open_time"]))
    assert all(len(h["open_time"]) == 5 and len(h["close_time"]) == 5 for h in normalized)
    assert _normalize_hours(normalized) == normalized
