import urllib.request
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/users?select=*&limit=1"
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Accept": "application/json"
}

req = urllib.request.Request(
    url,
    headers=headers,
    method="GET"
)

try:
    with urllib.request.urlopen(req) as r:
        data = json.loads(r.read().decode())
        if data:
            print("Users Table Columns:")
            for k in sorted(data[0].keys()):
                print(f"  - {k}: {type(data[0][k])} (Value: {data[0][k]})")
        else:
            print("No rows returned from users table.")
except Exception as e:
    print(f"Error: {e}")
