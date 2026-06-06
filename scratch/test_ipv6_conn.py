import psycopg2
import sys

host = "2406:da12:557:f803:68c8:e43:7806:ba83"
user = "postgres"
pwd = "kndeshxeerldamafweru"
dbname = "postgres"

try:
    print(f"Connecting to IPv6 address {host}...", flush=True)
    conn = psycopg2.connect(
        host=host,
        user=user,
        password=pwd,
        dbname=dbname,
        port=5432,
        connect_timeout=10
    )
    print("Connected successfully!", flush=True)
    conn.close()
    sys.exit(0)
except Exception as e:
    print(f"Failed: {e}", flush=True)
    sys.exit(1)
