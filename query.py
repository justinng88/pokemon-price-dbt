"""Run a SQL query against the project warehouse.

Runs from the analytics directory so relative paths in dbt sources
resolve exactly as they do during a dbt run.

Usage:
    python query.py "select count(*) from main.int_price_snapshots"
    python query.py -f scratch.sql

Schemas:
    main_staging   stg_ models
    main           int_ models
    main_marts     dim_ and fct_ models
"""

import argparse
import os
from pathlib import Path

import duckdb

parser = argparse.ArgumentParser()
parser.add_argument("sql", nargs="?", help="SQL to run")
parser.add_argument("-f", "--file", help="path to a .sql file to run instead")
args = parser.parse_args()

if args.file:
    p = Path(args.file)
    if not p.exists():
        parser.error(f"file not found: {p.resolve()}")
    sql = p.read_text()
    if not sql.strip():
        parser.error(f"file is empty: {p.resolve()}")
elif args.sql:
    sql = args.sql
else:
    parser.error("provide SQL inline or with -f")

os.chdir(Path(__file__).parent / "analytics")

con = duckdb.connect("../dev.duckdb", read_only=True)

result = con.sql(sql)
if result is not None:
    result.show(max_rows=50)
else:
    print("Statement executed; no rows returned.")