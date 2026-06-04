import urllib.request
import urllib.parse
import json

url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/"
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Accept": "application/json"
}

def check_table_and_column(table, column=None):
    params = {"limit": 1}
    if column:
        params["select"] = column
    query = urllib.parse.urlencode(params)
    req = urllib.request.Request(
        f"{url}{table}?{query}",
        headers=headers,
        method="GET"
    )
    try:
        with urllib.request.urlopen(req) as response:
            if column:
                print(f"Table '{table}' -> Column '{column}': EXISTS")
            else:
                print(f"Table '{table}': EXISTS")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        try:
            err_json = json.loads(err_body)
            msg = err_json.get("message", "")
        except:
            msg = err_body
        if column:
            print(f"Table '{table}' -> Column '{column}': ERROR/MISSING ({msg})")
        else:
            print(f"Table '{table}': ERROR/MISSING ({msg})")

check_table_and_column("reviews")
check_table_and_column("add_ons")
check_table_and_column("shifts")
check_table_and_column("shifts", "is_archived")
check_table_and_column("libraries", "location_link")
