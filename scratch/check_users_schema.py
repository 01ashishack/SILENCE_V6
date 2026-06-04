import urllib.request
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1"
headers = {
    "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY",
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"
}

req = urllib.request.Request(url)
for k, v in headers.items():
    req.add_header(k, v)

try:
    print("Fetching schema...")
    with urllib.request.urlopen(req) as response:
        html = response.read().decode('utf-8')
        data = json.loads(html)
        definitions = data.get("definitions", {})
        
        tables = ["users", "payments", "memberships", "attendance", "expenditures", "seats", "shifts", "floors", "sections"]
        for table in tables:
            print(f"\nTable: {table}")
            table_def = definitions.get(table, {})
            properties = table_def.get("properties", {})
            if not properties:
                print(" - No properties found / table doesn't exist in OpenAPI spec")
            for name, prop in properties.items():
                print(f" - {name}: {prop.get('type')} ({prop.get('format')})")
except Exception as e:
    print(f"Error: {e}")
