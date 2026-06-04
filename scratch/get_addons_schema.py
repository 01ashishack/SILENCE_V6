import urllib.request
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/"
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Accept": "application/json"
}

req = urllib.request.Request(url, headers=headers)

try:
    print("Fetching schema...")
    with urllib.request.urlopen(req) as response:
        html = response.read().decode('utf-8')
        data = json.loads(html)
        definitions = data.get("definitions", {})
        addons_def = definitions.get("add_ons", {})
        print("add_ons definition properties:")
        properties = addons_def.get("properties", {})
        for name, prop in properties.items():
            print(f" - {name}: {prop.get('type')} ({prop.get('format')})")
except Exception as e:
    print(f"Error: {e}")
