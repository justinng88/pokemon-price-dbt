#!/usr/bin/env python3
"""Extract Pokemon TCG catalog and price data from TCGCSV into a parquet landing zone.

TCGCSV is a public mirror of TCGplayer's categories, groups, products and prices.
Pokemon is categoryId 3. Groups are sets. Products are cards and sealed items.
Prices are keyed by (productId, subTypeName) and joined to products on productId.

Landing layout produced by this script:

    landing/groups/groups.parquet
    landing/products/products.parquet
    landing/product_attributes/product_attributes.parquet
    landing/prices/price_date=YYYY-MM-DD/prices.parquet

Usage:
    python extract/fetch_tcgcsv.py catalog
    python extract/fetch_tcgcsv.py prices --date today
    python extract/fetch_tcgcsv.py prices --start 2026-06-01 --end 2026-09-07

The catalog command hits live endpoints. The prices command hits live endpoints for
today and the daily archives for any past date.
"""

from __future__ import annotations

import argparse
import io
import json
import shutil
import sys
import tempfile
from datetime import date, datetime, timedelta
from pathlib import Path

import pandas as pd
import requests

CATEGORY_ID = 3  # Pokemon
BASE_URL = "https://tcgcsv.com/tcgplayer"
ARCHIVE_URL = "https://tcgcsv.com/archive/tcgplayer/prices-{d}.ppmd.7z"
LANDING = Path(__file__).resolve().parents[1] / "landing"
TIMEOUT = 60
USER_AGENT = "pokemon-price-dbt/0.1 (personal portfolio project)"

SESSION = requests.Session()
SESSION.headers.update({"User-Agent": USER_AGENT})


def get_json(url: str) -> list[dict]:
    resp = SESSION.get(url, timeout=TIMEOUT)
    resp.raise_for_status()
    payload = resp.json()
    if not payload.get("success", True):
        raise RuntimeError(f"TCGCSV reported failure for {url}")
    return payload.get("results", [])


def write_parquet(df: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(path, index=False)
    print(f"  wrote {len(df):>7,} rows -> {path.relative_to(LANDING.parent)}")


# ---------------------------------------------------------------- catalog


def fetch_catalog() -> None:
    """Pull groups (sets), products (cards), and the extendedData attribute rows.

    extendedData is a nested list on each product. It is flattened here into a long
    table so the landing zone stays rectangular; the pivot happens in dbt where it
    is visible and testable.
    """
    print("fetching groups")
    groups = get_json(f"{BASE_URL}/{CATEGORY_ID}/groups")
    write_parquet(pd.DataFrame(groups), LANDING / "groups" / "groups.parquet")

    product_rows: list[dict] = []
    attribute_rows: list[dict] = []

    for i, group in enumerate(groups, start=1):
        group_id = group["groupId"]
        print(f"fetching products {i}/{len(groups)}: {group.get('name')}")
        for product in get_json(f"{BASE_URL}/{CATEGORY_ID}/{group_id}/products"):
            extended = product.pop("extendedData", None) or []
            product_rows.append(product)
            for attr in extended:
                attribute_rows.append(
                    {
                        "productId": product["productId"],
                        "attributeName": attr.get("name"),
                        "attributeDisplayName": attr.get("displayName"),
                        "attributeValue": attr.get("value"),
                    }
                )

    write_parquet(
        pd.DataFrame(product_rows), LANDING / "products" / "products.parquet"
    )
    write_parquet(
        pd.DataFrame(attribute_rows),
        LANDING / "product_attributes" / "product_attributes.parquet",
    )


# ---------------------------------------------------------------- prices


def fetch_prices_live(price_date: date) -> None:
    """Today's prices, straight from the live per-group endpoints."""
    groups = get_json(f"{BASE_URL}/{CATEGORY_ID}/groups")
    rows: list[dict] = []
    for i, group in enumerate(groups, start=1):
        group_id = group["groupId"]
        print(f"fetching prices {i}/{len(groups)}: {group.get('name')}")
        for price in get_json(f"{BASE_URL}/{CATEGORY_ID}/{group_id}/prices"):
            price["groupId"] = group_id
            rows.append(price)
    _write_price_partition(rows, price_date)


def fetch_prices_archive(price_date: date) -> None:
    """A past date, from the daily archive. Archives start 2024-02-08."""
    try:
        import py7zr
    except ImportError:  # pragma: no cover
        sys.exit("py7zr is required for archive backfill: pip install py7zr")

    iso = price_date.isoformat()
    url = ARCHIVE_URL.format(d=iso)
    print(f"downloading archive {iso}")
    resp = SESSION.get(url, timeout=TIMEOUT * 5)
    if resp.status_code == 404:
        print(f"  no archive published for {iso}, skipping")
        return
    resp.raise_for_status()

    tmpdir = Path(tempfile.mkdtemp())
    try:
        with py7zr.SevenZipFile(io.BytesIO(resp.content), mode="r") as archive:
            archive.extractall(path=tmpdir)

        category_dir = tmpdir / iso / str(CATEGORY_ID)
        if not category_dir.exists():
            print(f"  archive {iso} has no category {CATEGORY_ID}, skipping")
            return

        rows: list[dict] = []
        for group_dir in sorted(category_dir.iterdir()):
            price_file = group_dir / "prices"
            if not price_file.exists():
                continue
            payload = json.loads(price_file.read_text())
            for price in payload.get("results", []):
                price["groupId"] = int(group_dir.name)
                rows.append(price)
        _write_price_partition(rows, price_date)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def _write_price_partition(rows: list[dict], price_date: date) -> None:
    if not rows:
        print(f"  no price rows for {price_date}, nothing written")
        return
    df = pd.DataFrame(rows)
    partition = LANDING / "prices" / f"price_date={price_date.isoformat()}"
    write_parquet(df, partition / "prices.parquet")


def fetch_prices(start: date, end: date) -> None:
    today = date.today()
    current = start
    while current <= end:
        partition = LANDING / "prices" / f"price_date={current.isoformat()}"
        if (partition / "prices.parquet").exists():
            print(f"skipping {current}, already landed")
        elif current >= today:
            fetch_prices_live(current)
        else:
            fetch_prices_archive(current)
        current += timedelta(days=1)


# ---------------------------------------------------------------- cli


def parse_day(value: str) -> date:
    if value == "today":
        return date.today()
    return datetime.strptime(value, "%Y-%m-%d").date()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("catalog", help="fetch groups, products and product attributes")

    prices = sub.add_parser("prices", help="fetch daily price snapshots")
    prices.add_argument("--date", type=parse_day, help="a single date, or 'today'")
    prices.add_argument("--start", type=parse_day, help="first date of a backfill")
    prices.add_argument("--end", type=parse_day, help="last date of a backfill")

    args = parser.parse_args()

    if args.command == "catalog":
        fetch_catalog()
        return

    if args.date:
        fetch_prices(args.date, args.date)
    elif args.start and args.end:
        fetch_prices(args.start, args.end)
    else:
        parser.error("prices requires either --date or both --start and --end")


if __name__ == "__main__":
    main()
