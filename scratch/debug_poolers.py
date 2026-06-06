import socket
import psycopg2
import sys

regions = [
    "ap-south-1",      # Mumbai
    "ap-southeast-1",  # Singapore
    "ap-southeast-2",  # Sydney
    "ap-northeast-1",  # Tokyo
    "ap-northeast-2",  # Seoul
    "us-east-1",       # N. Virginia
    "us-east-2",       # Ohio
    "us-west-1",       # N. California
    "us-west-2",       # Oregon
    "eu-central-1",    # Frankfurt
    "eu-west-1",       # Ireland
    "eu-west-2",       # London
    "sa-east-1",       # Sao Paulo
    "ca-central-1"     # Canada
]

passwords = [
    "postgres",
    "postgres123",
    "kndeshxeerldamafweru",
    "supabase",
    "admin",
    "admin123",
    "silence",
    "silence123",
    "password",
    "root",
    "root123",
    "Silence_V6",
    "SilenceV6",
    "Silence"
]

project_ref = "kndeshxeerldamafweru"
username = f"postgres.{project_ref}"
dbname = "postgres"
port = 6543

print("Starting debug poolers script...", flush=True)

for region in regions:
    pooler_host = f"aws-0-{region}.pooler.supabase.com"
    try:
        ip = socket.gethostbyname(pooler_host)
        print(f"[{region}] Resolved {pooler_host} to {ip}", flush=True)
    except Exception as e:
        print(f"[{region}] Failed to resolve {pooler_host}: {e}", flush=True)
        continue

    for pwd in passwords:
        try:
            conn = psycopg2.connect(
                host=pooler_host,
                user=username,
                password=pwd,
                dbname=dbname,
                port=port,
                connect_timeout=3
            )
            print(f"[{region}] SUCCESS WITH PASSWORD '{pwd}'!", flush=True)
            conn.close()
            sys.exit(0)
        except psycopg2.OperationalError as e:
            err = str(e).strip().replace("\n", " ")
            print(f"[{region}] Pwd '{pwd}' failed: {err}", flush=True)
        except Exception as e:
            print(f"[{region}] Unexpected: {e}", flush=True)

print("Finished debug script. No connection succeeded.", flush=True)
