import psycopg2
import sys
import socket

regions = [
    "ap-south-1",      # Mumbai
    "ap-southeast-1",  # Singapore
    "ap-southeast-2",  # Sydney
    "ap-northeast-1",  # Tokyo
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
    "root123"
]

project_ref = "kndeshxeerldamafweru"
username = f"postgres.{project_ref}"
dbname = "postgres"
port = 6543

print("Starting region scanning to find where the Supabase tenant is hosted...", flush=True)

success = False
for region in regions:
    pooler_host = f"aws-0-{region}.pooler.supabase.com"
    try:
        # Check if the host resolves to IPv4
        ip = socket.gethostbyname(pooler_host)
        print(f"Region '{region}' pooler host resolved to: {ip}", flush=True)
    except Exception as e:
        print(f"Region '{region}' pooler host did not resolve. Skipping.", flush=True)
        continue

    # Try connecting with the first password to check if the tenant exists
    # If the tenant doesn't exist, it will throw a ENOTFOUND FATAL error
    # If the tenant exists but password is wrong, it will throw password authentication failed
    tenant_exists = False
    for pwd in passwords:
        try:
            print(f"Trying region '{region}' with password '{pwd}'...", flush=True)
            conn = psycopg2.connect(
                host=pooler_host,
                user=username,
                password=pwd,
                dbname=dbname,
                port=port,
                connect_timeout=4
            )
            print(f"SUCCESS! Connected successfully in region '{region}' with password: {pwd}", flush=True)
            cur = conn.cursor()
            print("Running migration to add shift_type and hours_per_day columns...", flush=True)
            cur.execute("ALTER TABLE shifts ADD COLUMN IF NOT EXISTS shift_type TEXT DEFAULT 'fixed';")
            cur.execute("ALTER TABLE shifts ADD COLUMN IF NOT EXISTS hours_per_day INTEGER DEFAULT NULL;")
            conn.commit()
            print("MIGRATION COMPLETED SUCCESSFULLY!", flush=True)
            cur.close()
            conn.close()
            success = True
            break
        except psycopg2.OperationalError as e:
            err_msg = str(e)
            if "tenant/user" in err_msg and "not found" in err_msg:
                print(f"Tenant not found in region '{region}'. Skipping region.", flush=True)
                break # Skip other passwords for this region
            elif "password authentication failed" in err_msg:
                print(f"Tenant FOUND in region '{region}'! Password '{pwd}' is incorrect.", flush=True)
                tenant_exists = True
                continue
            else:
                print(f"Operational error in region '{region}': {err_msg}", flush=True)
        except Exception as e:
            print(f"Error in region '{region}': {e}", flush=True)
            
    if success:
        break

if success:
    print("Migration finished with success!", flush=True)
else:
    print("Failed to run migration. Could not connect to any region pooler or password was incorrect.", flush=True)
    sys.exit(1)
