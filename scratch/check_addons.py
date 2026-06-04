import urllib.request
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/add_ons?limit=1"
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Accept": "application/json",
    "Range-Unit": "items",
    "Range": "0-0"
}

req = urllib.request.Request(url, headers=headers)

try:
    print("Fetching add_ons record...")
    with urllib.request.urlopen(req) as response:
        headers_res = response.info()
        print("Response headers:")
        print(headers_res)
        html = response.read().decode('utf-8')
        print("Response body:")
        print(html)
except Exception as e:
    print(f"Error: {e}")
