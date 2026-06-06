import urllib.request
import json

anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY"
base_url = "https://kndeshxeerldamafweru.supabase.co/rest/v1/"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Accept": "application/json"
}

req = urllib.request.Request(base_url, headers=headers)
try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode('utf-8'))
        paths = data.get('paths', {})
        # Find paths related to seat_change_requests
        scr_path = paths.get('/seat_change_requests', {})
        post_parameters = scr_path.get('post', {}).get('parameters', [])
        columns = []
        for param in post_parameters:
            if param.get('in') == 'body':
                schema = param.get('schema', {})
                properties = schema.get('properties', {})
                columns = list(properties.keys())
                break
        print(f"seat_change_requests columns: {columns}")
        
        # Check sections path too
        sec_path = paths.get('/sections', {})
        sec_post_params = sec_path.get('post', {}).get('parameters', [])
        sec_columns = []
        for param in sec_post_params:
            if param.get('in') == 'body':
                schema = param.get('schema', {})
                properties = schema.get('properties', {})
                sec_columns = list(properties.keys())
                break
        print(f"sections columns: {sec_columns}")
except Exception as e:
    print(f"Failed: {e}")
