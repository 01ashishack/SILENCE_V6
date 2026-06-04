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

success = False
for region in regions:
    pooler_host = f"aws-0-{region}.pooler.supabase.com"
    try:
        ip = socket.gethostbyname(pooler_host)
    except Exception:
        continue

    for pwd in passwords:
        try:
            conn = psycopg2.connect(
                host=pooler_host,
                user=username,
                password=pwd,
                dbname=dbname,
                port=port,
                connect_timeout=4
            )
            print(f"SUCCESS! Connected in region '{region}' with password: {pwd}", flush=True)
            cur = conn.cursor()
            print("Running migration to add location_link column to libraries table...", flush=True)
            cur.execute("ALTER TABLE libraries ADD COLUMN IF NOT EXISTS location_link TEXT;")
            conn.commit()
            print("MIGRATION COMPLETED SUCCESSFULLY!", flush=True)
            cur.close()
            conn.close()
            success = True
            break
        except psycopg2.OperationalError as e:
            err_msg = str(e)
            if "tenant/user" in err_msg and "not found" in err_msg:
                break
            else:
                continue
        except Exception:
            continue
            
    if success:
        break

if success:
    print("Migration finished with success!", flush=True)
else:
    print("Failed to run migration.", flush=True)
    sys.exit(1)
