import urllib.request
import urllib.parse
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/"
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Accept": "application/json",
    "Prefer": "count=exact"
}

req = urllib.request.Request(
    f"{url}queries?select=*&limit=1",
    headers=headers,
    method="GET"
)

try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode())
        if data:
            print("Columns in queries table:", list(data[0].keys()))
        else:
            print("queries table is empty, trying to query schema metadata...")
            # We can request options or head to see headers
            req2 = urllib.request.Request(
                f"{url}queries",
                headers={**headers, "Prefer": "return=representation"},
                method="OPTIONS"
            )
            with urllib.request.urlopen(req2) as resp2:
                print("OPTIONS headers:", dict(resp2.info()))
                body = resp2.read().decode()
                try:
                    schema = json.loads(body)
                    print("Table schema details:")
                    for table in schema.get("definitions", {}).keys():
                        if "queries" in table:
                            print(table, schema["definitions"][table])
                except Exception as e:
                    print("Failed parsing OPTIONS body:", e, body[:1000])
except Exception as e:
    print("Error:", e)
