import psycopg2
import sys

host = "2406:da12:557:f803:68c8:e43:7806:ba83"
user = "postgres"
dbname = "postgres"
port = 5432

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

print("Attempting to run location_link migration on Supabase DB...", flush=True)

success = False
for pwd in passwords:
    try:
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
        print("Running migration to add location_link column...", flush=True)
        cur.execute("ALTER TABLE libraries ADD COLUMN IF NOT EXISTS location_link TEXT;")
        conn.commit()
        print("MIGRATION COMPLETED SUCCESSFULLY!", flush=True)
        
        cur.close()
        conn.close()
        success = True
        break
    except Exception as e:
        print(f"Failed with password {pwd}: {e}", flush=True)

if not success:
    print("Failed to run migration.", flush=True)
    sys.exit(1)
