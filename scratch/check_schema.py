import urllib.request
import json

anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"
base_url = "https://kndeshxeerldamafweru.supabase.co/rest/v1"

tables = ['users', 'payments', 'memberships', 'attendance', 'expenditures', 'seats', 'shifts', 'floors', 'sections']

for table in tables:
    url = f"{base_url}/{table}?limit=1"
    headers = {
        "apikey": anon_key,
        "Authorization": f"Bearer {anon_key}"
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as response:
            html = response.read().decode('utf-8')
            print(f"Table {table} raw: {html}")
    except Exception as e:
        print(f"Table {table} failed: {e}")
