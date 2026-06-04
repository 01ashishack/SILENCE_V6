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

cols_to_check = [
    "id", "library_id", "member_id", "subject", "message", "type", "status", "created_at"
]

print("Checking queries table columns:")
for col in cols_to_check:
    query = urllib.parse.urlencode({"select": col, "limit": 1})
    req = urllib.request.Request(
        f"{url}queries?{query}",
        headers=headers,
        method="GET"
    )
    try:
        with urllib.request.urlopen(req) as response:
            print(f"  - Column '{col}': EXISTS")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        try:
            err_json = json.loads(err_body)
            msg = err_json.get("message", "")
        except:
            msg = err_body
        if "column" in msg.lower() or "not found" in msg.lower() or "does not exist" in msg.lower():
            print(f"  - Column '{col}': MISSING ({msg})")
        else:
            print(f"  - Column '{col}': Error {e.code} - {msg}")
