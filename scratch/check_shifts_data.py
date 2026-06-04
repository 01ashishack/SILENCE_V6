import urllib.request
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/shifts?select=*"
headers = {
    "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY",
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"
}

req = urllib.request.Request(url)
for k, v in headers.items():
    req.add_header(k, v)

try:
    print("Fetching shifts...")
    with urllib.request.urlopen(req) as response:
        html = response.read().decode('utf-8')
        data = json.loads(html)
        print(f"Total shifts found: {len(data)}")
        for index, item in enumerate(data):
            print(f"[{index}] ID: {item['id']}, Library: {item['library_id']}, Name: {item['name']}, Archived: {item['is_archived']}")
except Exception as e:
    print(f"Error: {e}")
