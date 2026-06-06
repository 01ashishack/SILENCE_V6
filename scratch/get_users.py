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

query = urllib.parse.urlencode({"select": "id,email,full_name,role", "limit": 10})
req = urllib.request.Request(
    f"{url}users?{query}",
    headers=headers,
    method="GET"
)

try:
    with urllib.request.urlopen(req) as response:
        users = json.loads(response.read().decode())
        for u in users:
            print(f"ID: {u.get('id')} | Email: {u.get('email')} | Name: {u.get('full_name')} | Role: {u.get('role')}")
except Exception as e:
    print("Error:", e)
