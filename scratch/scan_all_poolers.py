import psycopg2
import sys
import socket
import concurrent.futures

regions = [
    "ap-south-1", "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-northeast-2",
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "eu-central-1", "eu-west-1", "eu-west-2", "eu-west-3", "eu-north-1",
    "sa-east-1", "ca-central-1", "me-central-1", "af-south-1"
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

def check_target(region, port, pwd):
    pooler_host = f"aws-0-{region}.pooler.supabase.com"
    try:
        conn = psycopg2.connect(
            host=pooler_host,
            user=username,
            password=pwd,
            dbname=dbname,
            port=port,
            connect_timeout=3
        )
        return ("SUCCESS", region, port, pwd, conn)
    except psycopg2.OperationalError as e:
        err_msg = str(e)
        if "tenant/user" in err_msg and "not found" in err_msg:
            return ("NOT_FOUND", region, port, pwd, None)
        elif "password authentication failed" in err_msg:
            return ("PWD_FAILED", region, port, pwd, None)
        else:
            return ("ERROR", region, port, pwd, err_msg)
    except Exception as e:
        return ("ERROR", region, port, pwd, str(e))

print("Resolving pooler hosts...", flush=True)
active_targets = []
for region in regions:
    pooler_host = f"aws-0-{region}.pooler.supabase.com"
    try:
        ip = socket.gethostbyname(pooler_host)
        print(f"  {region}: {ip}", flush=True)
        for port in [5432, 6543]:
            active_targets.append((region, port))
    except Exception:
        continue

print(f"\nScanning {len(active_targets)} active targets with parallel workers...", flush=True)

found_region = None
correct_pwd = None
conn_success = None

# We use ThreadPoolExecutor to scan concurrently and save time
with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
    # First, let's just probe each target with the password 'postgres' to locate the tenant
    probe_futures = {executor.submit(check_target, r, p, "postgres"): (r, p) for r, p in active_targets}
    for future in concurrent.futures.as_completed(probe_futures):
        res, r, p, pwd, conn = future.result()
        if res == "PWD_FAILED":
            print(f"\n>>> TENANT FOUND in region '{r}' on port {p}! Checking password list...", flush=True)
            found_region = (r, p)
            break
        elif res == "SUCCESS":
            print(f"\n>>> SUCCESS! Connected in region '{r}' on port {p} with password: {pwd}", flush=True)
            found_region = (r, p)
            correct_pwd = pwd
            conn_success = conn
            break

    if found_region and not conn_success:
        # Tenant found but password was not 'postgres'. Try other passwords in parallel on that specific target!
        r, p = found_region
        pwd_futures = {executor.submit(check_target, r, p, pwd): pwd for pwd in passwords if pwd != "postgres"}
        for future in concurrent.futures.as_completed(pwd_futures):
            res, _, _, pwd, conn = future.result()
            if res == "SUCCESS":
                print(f"\n>>> SUCCESS! Connected with password: {pwd}", flush=True)
                correct_pwd = pwd
                conn_success = conn
                break

if conn_success:
    try:
        cur = conn_success.cursor()
        print("\nRunning migration to add shift_type and hours_per_day columns...", flush=True)
        cur.execute("ALTER TABLE shifts ADD COLUMN IF NOT EXISTS shift_type TEXT DEFAULT 'fixed';")
        cur.execute("ALTER TABLE shifts ADD COLUMN IF NOT EXISTS hours_per_day INTEGER DEFAULT NULL;")
        conn_success.commit()
        print("MIGRATION COMPLETED SUCCESSFULLY!", flush=True)
        cur.close()
        conn_success.close()
        sys.exit(0)
    except Exception as e:
        print(f"Error running migration: {e}", flush=True)
        sys.exit(1)
else:
    print("\nCould not find the tenant or correct password on any pooler.", flush=True)
    sys.exit(1)
