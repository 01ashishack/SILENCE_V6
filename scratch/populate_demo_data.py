import json
import urllib.request
import urllib.error
from datetime import datetime, timezone

URL_PREFIX = "https://kndeshxeerldamafweru.supabase.co/rest/v1"
HEADERS = {
    "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY",
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtuZGVzaHhlZXJsZGFtYWZ3ZXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MTk5NTQsImV4cCI6MjA5NTE5NTk1NH0.G2fdi683tCWQHWnWlOc1xTOustbch1-rrXnIRZWILRY",
    "Content-Type": "application/json",
    "Prefer": "resolution=merge-duplicates"
}

def post_data(table, data_list):
    url = f"{URL_PREFIX}/{table}"
    payload = json.dumps(data_list).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req) as res:
            print(f"SUCCESS: Inserted {len(data_list)} rows into '{table}' (Status: {res.status})")
    except urllib.error.HTTPError as e:
        print(f"FAILURE: Failed to insert into '{table}'. HTTP Error: {e.code} {e.reason}")
        print("Response:", e.read().decode("utf-8"))

def main():
    print("--- POPULATING REAL DEMO DATA FOR AZAD LIBRARY ---")
    
    # 1. Insert Users (Admin + Members)
    users = [
        {
            "id": "5db67d18-fd2b-45b0-a25f-f95644ab9def",
            "email": "owner@silence.com",
            "full_name": "Azad Owner",
            "nickname": "Azad",
            "role": "admin"
        },
        {
            "id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
            "email": "member1@silence.com",
            "full_name": "Ashish Sharma",
            "nickname": "Ashish",
            "role": "member",
            "phone": "9876543210",
            "gender": "male",
            "exam_category": "UPSC"
        },
        {
            "id": "b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e",
            "email": "member2@silence.com",
            "full_name": "Priya Patel",
            "nickname": "Priya",
            "role": "member",
            "phone": "9876543211",
            "gender": "female",
            "exam_category": "CAT"
        }
    ]
    post_data("users", users)

    # 2. Insert Memberships
    memberships = [
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "member_id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
            "library_id": "6bdd5d6a-29e5-4152-91c2-ce04c86d1f59",
            "shift_id": "9fd014c0-7b17-42f5-a2a5-e26c55adf65a",
            "seat_id": "60f8c201-3d6f-4352-8732-25e8be534e9c",
            "start_date": "2026-06-01",
            "end_date": "2026-06-30",
            "status": "active",
            "amount": 1200,
            "plan_type": "Monthly"
        },
        {
            "id": "22222222-3333-4444-5555-666666666666",
            "member_id": "b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e",
            "library_id": "6bdd5d6a-29e5-4152-91c2-ce04c86d1f59",
            "shift_id": "9fd014c0-7b17-42f5-a2a5-e26c55adf65a",
            "seat_id": "60f8c201-3d6f-4352-8732-25e8be534e9c",
            "start_date": "2026-06-01",
            "end_date": "2026-06-30",
            "status": "active",
            "amount": 1500,
            "plan_type": "Monthly"
        }
    ]
    post_data("memberships", memberships)

    # 3. Insert Payments (confirmed + pending dues)
    payments = [
        {
            "id": "33333333-4444-5555-6666-777777777777",
            "membership_id": "11111111-2222-3333-4444-555555555555",
            "member_id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
            "library_id": "6bdd5d6a-29e5-4152-91c2-ce04c86d1f59",
            "amount": 1200,
            "payment_method": "UPI",
            "status": "confirmed",
            "payment_date": "2026-06-02T10:00:00Z"
        },
        {
            "id": "44444444-5555-6666-7777-888888888888",
            "membership_id": "22222222-3333-4444-5555-666666666666",
            "member_id": "b2c3d4e5-f6a7-8b9c-0d1e-2f3a4b5c6d7e",
            "library_id": "6bdd5d6a-29e5-4152-91c2-ce04c86d1f59",
            "amount": 1500,
            "payment_method": "Cash",
            "status": "pending",
            "payment_date": "2026-06-02T11:00:00Z"
        }
    ]
    post_data("payments", payments)

    # 4. Insert Attendance check-in for Member 1
    attendance = [
        {
            "id": "55555555-6666-7777-8888-999999999999",
            "membership_id": "11111111-2222-3333-4444-555555555555",
            "member_id": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
            "library_id": "6bdd5d6a-29e5-4152-91c2-ce04c86d1f59",
            "shift_id": "9fd014c0-7b17-42f5-a2a5-e26c55adf65a",
            "check_in_time": "2026-06-02T08:30:00Z",
            "check_out_time": None,
            "session_type": "normal",
            "qr_version": 1
        }
    ]
    post_data("attendance", attendance)

    # 5. Set seat status to occupied for Seat B-16
    print("All demo data populated.")

if __name__ == "__main__":
    main()
