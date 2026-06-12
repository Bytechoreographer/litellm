"""Generate a data-only SQL seed from litellm_dev, excluding heavy analytics tables.

Output is a psql-loadable file using COPY blocks (handles json/array/null natively).
Load flow (local): start empty postgres -> proxy builds schema via prisma -> psql -f this file.
session_replication_role=replica disables FK/triggers during load so table order is irrelevant.
"""
import os
import psycopg

DEV_DB_URL = os.environ["DEV_DB_URL"]
OUT = os.path.join(os.path.dirname(__file__), "litellm_dev_seed.sql")

# Heavy analytics / log tables: schema is recreated by prisma, data not needed for dev.
EXCLUDE = {
    "LiteLLM_DailyEndUserSpend",
    "LiteLLM_DailyTagSpend",
    "LiteLLM_DailyTeamSpend",
    "LiteLLM_DailyUserSpend",
    "LiteLLM_EndUserTable",
    "LiteLLM_SpendLogs",
    "LiteLLM_SpendLogToolIndex",
    "_prisma_migrations",
}

with psycopg.connect(DEV_DB_URL, connect_timeout=20) as conn, open(OUT, "w") as f:
    with conn.cursor() as cur:
        cur.execute(
            "select table_name from information_schema.tables "
            "where table_schema='public' and table_type='BASE TABLE' order by table_name"
        )
        tables = [r[0] for r in cur.fetchall() if r[0] not in EXCLUDE]

    f.write("-- litellm_dev data-only seed (heavy analytics tables excluded)\n")
    f.write("SET session_replication_role = replica;\n\n")

    total_rows = 0
    with conn.cursor() as cur:
        for t in tables:
            cur.execute(
                "select column_name from information_schema.columns "
                "where table_schema='public' and table_name=%s "
                "and is_generated='NEVER' order by ordinal_position",
                (t,),
            )
            cols = [r[0] for r in cur.fetchall()]
            if not cols:
                continue
            collist = ", ".join(f'"{c}"' for c in cols)
            cur.execute(f'select count(*) from "{t}"')
            n = cur.fetchone()[0]
            if n == 0:
                continue
            total_rows += n
            f.write(f'COPY "{t}" ({collist}) FROM stdin;\n')
            with cur.copy(f'COPY "{t}" ({collist}) TO STDOUT (FORMAT text)') as copy:
                for data in copy:
                    f.write(bytes(data).decode("utf-8", "surrogateescape"))
            f.write("\\.\n\n")
            print(f"  {t:42} {n:>8} rows")

    f.write("SET session_replication_role = origin;\n")
    print(f"\nwrote {OUT}  ({total_rows} data rows across {len(tables)} candidate tables)")
