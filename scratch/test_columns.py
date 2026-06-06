import urllib.request
import urllib.error
import json

anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"
base_url = "https://kndeshxeerldamafweru.supabase.co/rest/v1"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Content-Type": "application/json",
    "Prefer": "return=minimal"
}

# Test preferred_section_id in seat_change_requests
url = f"{base_url}/seat_change_requests"
payload = {"preferred_section_id": "11111111-2222-3333-4444-555555555555"}
req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers=headers, method="POST")

try:
    with urllib.request.urlopen(req) as response:
        print("preferred_section_id test: SUCCESS (column exists)")
except urllib.error.HTTPError as e:
    resp = e.read().decode('utf-8')
    if "preferred_section_id" in resp:
        print("preferred_section_id test: FAILED (column does not exist)")
    else:
        print(f"preferred_section_id test: column exists (failed due to other reasons: {resp})")
except Exception as e:
    print(f"Error: {e}")

# Check sections columns by doing a GET
url_sec = f"{base_url}/sections?limit=1"
req_sec = urllib.request.Request(url_sec, headers=headers)
try:
    with urllib.request.urlopen(req_sec) as response:
        data = json.loads(response.read().decode('utf-8'))
        if data:
            print(f"sections columns: {list(data[0].keys())}")
        else:
            print("sections table is empty.")
except Exception as e:
    print(f"Failed to get sections: {e}")
