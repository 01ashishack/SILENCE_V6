import urllib.request
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/"
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Accept": "application/json",
    "Prefer": "count=exact"
}

# Fetch OpenAPI definition to get users table columns
req = urllib.request.Request(
    url,
    headers=headers,
    method="GET"
)

try:
    with urllib.request.urlopen(req) as r:
        spec = json.loads(r.read().decode())
        properties = spec.get("definitions", {}).get("users", {}).get("properties", {})
        print("Users Table Columns:")
        for col_name, col_info in sorted(properties.items()):
            print(f"  - {col_name}: {col_info.get('type')} (Format: {col_info.get('format', 'N/A')})")
except Exception as e:
    print(f"Error: {e}")
