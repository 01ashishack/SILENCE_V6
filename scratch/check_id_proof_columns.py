import urllib.request
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/users"
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"

# Let's test a set of possible column names by attempting to select them.
# If they do not exist, PostgREST will return a 400 Bad Request with an error message listing the missing columns.
columns_to_test = [
    "id_proof_status", "id_proof_status_2", 
    "id_proof_1_status", "id_proof_2_status", 
    "id_proof_status_1", "id_proof_2_status",
    "phone_verified", "email_verified",
    "scheduled_for_deletion", "deletion_scheduled_at",
    "show_on_leaderboard", "show_hours", "hide_nickname",
    "accepted_terms_version", "id_proof_2_url", "id_doc_type_1", "id_doc_type_2"
]

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Accept": "application/json"
}

for col in columns_to_test:
    req_url = f"{url}?select={col}&limit=1"
    req = urllib.request.Request(req_url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req) as r:
            print(f"Column '{col}': EXISTS")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        if "not found" in err_body.lower() or "does not exist" in err_body.lower():
            print(f"Column '{col}': MISSING")
        else:
            print(f"Column '{col}': Server returned error {e.code} - {err_body}")
