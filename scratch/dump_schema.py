import urllib.request
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/"
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
        spec = json.loads(r.read().decode())
        definitions = spec.get("definitions", {})
        for name, definition in definitions.items():
            if name in ["users", "libraries", "memberships", "seats", "verification_requests"]:
                properties = definition.get("properties", {})
                cols = []
                for prop_name, prop_val in properties.items():
                    cols.append(f"{prop_name} ({prop_val.get('type', 'unknown')})")
                print(f"Table '{name}':")
                for c in sorted(cols):
                    print(f"  - {c}")
except Exception as e:
    print(f"Error fetching schema: {e}")
