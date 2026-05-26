import urllib.request
import urllib.error
import sys

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/"
print(f"Sending request to {url}...", flush=True)

try:
    req = urllib.request.Request(
        url,
        headers={"apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"}
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        print("Response headers:")
        for name, value in response.getheaders():
            print(f"  {name}: {value}", flush=True)
except urllib.error.HTTPError as e:
    print(f"HTTP Error {e.code}: {e.reason}", flush=True)
    print("Error response headers:")
    for name, value in e.headers.items():
        print(f"  {name}: {value}", flush=True)
except Exception as e:
    print(f"Failed: {e}", flush=True)
