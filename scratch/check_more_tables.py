import urllib.request
import urllib.parse
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/"
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Accept": "application/json"
}

tables_to_check = ["floors", "sections", "shifts", "attendance"]

for table in tables_to_check:
    print(f"\nChecking table '{table}':")
    req = urllib.request.Request(
        f"{url}{table}?limit=1",
        headers=headers,
        method="GET"
    )
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            if data:
                print(f"  - Table '{table}': EXISTS. Columns: {list(data[0].keys())}")
            else:
                print(f"  - Table '{table}': EXISTS (0 rows)")
    except urllib.error.HTTPError as e:
        print(f"  - Table '{table}': Error {e.code} - {e.reason}")
