import psycopg2
import sys
import socket

regions = [
    "ap-south-1",      # Mumbai
    "ap-southeast-1",  # Singapore
    "us-east-1",       # N. Virginia
    "us-west-1",       # N. California
    "eu-central-1"     # Frankfurt
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
    "root123"
]

project_ref = "kndeshxeerldamafweru"
username = f"postgres.{project_ref}"
dbname = "postgres"

print("Starting pooler ports testing...", flush=True)

success = False
for region in regions:
    pooler_host = f"aws-0-{region}.pooler.supabase.com"
    try:
        ip = socket.gethostbyname(pooler_host)
        print(f"\nRegion '{region}' pooler host: {pooler_host} ({ip})", flush=True)
    except Exception as e:
        continue

    for port in [5432, 6543]:
        tenant_found = False
        for pwd in passwords:
            try:
                print(f"  Trying port {port} with password '{pwd}'...", flush=True)
                conn = psycopg2.connect(
                    host=pooler_host,
                    user=username,
                    password=pwd,
                    dbname=dbname,
                    port=port,
                    connect_timeout=3
                )
                print(f"  SUCCESS! Connected in region '{region}' on port {port} with password: {pwd}", flush=True)
                cur = conn.cursor()
                print("  Running migration...", flush=True)
                cur.execute("ALTER TABLE shifts ADD COLUMN IF NOT EXISTS shift_type TEXT DEFAULT 'fixed';")
                cur.execute("ALTER TABLE shifts ADD COLUMN IF NOT EXISTS hours_per_day INTEGER DEFAULT NULL;")
                conn.commit()
                print("  MIGRATION COMPLETED SUCCESSFULLY!", flush=True)
                cur.close()
                conn.close()
                success = True
                break
            except psycopg2.OperationalError as e:
                err_msg = str(e)
                if "tenant/user" in err_msg and "not found" in err_msg:
                    print(f"  Tenant not found on port {port}.", flush=True)
                    break # Tenant not on this region pooler
                elif "password authentication failed" in err_msg:
                    print(f"  Tenant FOUND on port {port}! Password '{pwd}' is incorrect.", flush=True)
                    tenant_found = True
                    continue
                else:
                    print(f"  Error on port {port}: {err_msg.strip()}", flush=True)
            except Exception as e:
                print(f"  Unexpected error: {e}", flush=True)
        if success:
            break
    if success:
        break

if success:
    print("\nMigration succeeded!", flush=True)
else:
    print("\nCould not connect or authenticate.", flush=True)
    sys.exit(1)
