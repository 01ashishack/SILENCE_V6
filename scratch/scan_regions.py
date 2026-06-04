import psycopg2
import socket

regions = [
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "ap-south-1", "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-northeast-2", "ap-northeast-3", "ap-southeast-3",
    "eu-central-1", "eu-west-1", "eu-west-2", "eu-west-3", "eu-south-1", "eu-north-1",
    "sa-east-1", "ca-central-1", "me-central-1", "af-south-1"
]

project_ref = "kndeshxeerldamafweru"
username = f"postgres.{project_ref}"
dbname = "postgres"
port = 6543

print("Scanning regions...")
for region in regions:
    pooler_host = f"aws-0-{region}.pooler.supabase.com"
    try:
        ip = socket.gethostbyname(pooler_host)
    except Exception:
        continue
    
    try:
        conn = psycopg2.connect(
            host=pooler_host,
            user=username,
            password="dummy_password_to_test_tenant",
            dbname=dbname,
            port=port,
            connect_timeout=3
        )
        conn.close()
        print(f"Region '{region}' -> Tenant FOUND and connected (dummy password worked??)!")
    except psycopg2.OperationalError as e:
        err_msg = str(e)
        if "tenant/user" in err_msg and "not found" in err_msg:
            # Tenant does not exist in this region
            pass
        elif "password authentication failed" in err_msg:
            print(f"Region '{region}' -> Tenant EXISTS! (Password authentication failed as expected)")
        else:
            print(f"Region '{region}' -> Operational Error: {err_msg.strip()}")
    except Exception as e:
        print(f"Region '{region}' -> Error: {e}")
