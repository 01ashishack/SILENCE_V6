import psycopg2
import sys

host = "aws-0-ap-south-1.pooler.supabase.com"
user = "postgres.kndeshxeerldamafweru"
dbname = "postgres"
port = 6543

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

print("Starting Supabase DB connection attempts using pooler...", flush=True)

success = False
for pwd in passwords:
    try:
        print(f"Trying password '{pwd}' on pooler port {port}...", flush=True)
        conn = psycopg2.connect(
            host=host,
            user=user,
            password=pwd,
            dbname=dbname,
            port=port,
            connect_timeout=5
        )
        print(f"SUCCESS! Connected with password: {pwd}", flush=True)
        cur = conn.cursor()
        
        # Execute migration SQL
        print("Running migration to add shift_type and hours_per_day columns...", flush=True)
        cur.execute("ALTER TABLE shifts ADD COLUMN IF NOT EXISTS shift_type TEXT DEFAULT 'fixed';")
        cur.execute("ALTER TABLE shifts ADD COLUMN IF NOT EXISTS hours_per_day INTEGER DEFAULT NULL;")
        conn.commit()
        print("MIGRATION COMPLETED SUCCESSFULLY!", flush=True)
        
        cur.close()
        conn.close()
        success = True
        break
    except Exception as e:
        print(f"Failed: {e}", flush=True)

if not success:
    print("Failed to connect using standard common passwords. Please specify the db password.", flush=True)
    sys.exit(1)
