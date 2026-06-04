import urllib.request
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/add_ons?limit=1"
headers = {
    "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY",
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"
}

req = urllib.request.Request(url)
for k, v in headers.items():
    req.add_header(k, v)

try:
    print("Fetching add_ons row from REST API...")
    with urllib.request.urlopen(req) as response:
        html = response.read().decode('utf-8')
        data = json.loads(html)
        if data and len(data) > 0:
            print("Available columns in 'add_ons' table:")
            print(list(data[0].keys()))
            print("\nExample data:")
            print(data[0])
        else:
            print("No rows found in add_ons table.")
except Exception as e:
    print(f"Error: {e}")
