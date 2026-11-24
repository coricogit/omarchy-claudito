"""Which season it is where you live, for Claudito's seasonal clothes."""
import datetime as dt
import os

SEASONS = ("spring", "summer", "autumn", "winter")

# First day of each season in the northern hemisphere (the equinoxes and
# solstices move a day or so between years).
STARTS = (((3, 20), "spring"), ((6, 21), "summer"), ((9, 22), "autumn"), ((12, 21), "winter"))
OPPOSITE = {"spring": "autumn", "summer": "winter", "autumn": "spring", "winter": "summer"}

# Countries with (nearly) all their people south of the equator.
SOUTHERN = set("AO AR AU BI BO BR BW CD CG CL FJ ID KM LS MG MU MW MZ NA NC NZ PE PF PG PY "
               "RE RW SB SC SZ TL TO TZ UY VU WS ZA ZM ZW".split())


def season_on(day, southern=False):
    name = "winter"   # before the first start of the year
    for start, season in STARTS:
        if (day.month, day.day) >= start:
            name = season
    return OPPOSITE[name] if southern else name


def timezone():
    """Name of the system time zone, such as "America/Mexico_City", or ""."""
    try:
        path = os.path.realpath("/etc/localtime")
    except OSError:
        return ""
    return path.partition("/zoneinfo/")[2]


def country(zone=None, table="/usr/share/zoneinfo/zone.tab"):
    """Two-letter code of the country you are in: the one of your time zone,
    or else of your language settings. The language alone says little:
    en_US is used all over the world."""
    zone = timezone() if zone is None else zone
    try:
        with open(table, encoding="utf-8") as f:
            for line in f:
                cols = line.rstrip("\n").split("\t")
                if len(cols) > 2 and not line.startswith("#") and cols[2] == zone:
                    return cols[0].upper()
    except (OSError, ValueError):
        pass
    lang = os.environ.get("LC_ALL") or os.environ.get("LC_TIME") or os.environ.get("LANG") or ""
    return lang.partition(".")[0].partition("_")[2].upper()


def current():
    return season_on(dt.date.today(), country() in SOUTHERN)
