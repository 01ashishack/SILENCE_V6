with open("lib/screens/admin_home.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

for idx, line in enumerate(lines):
    if "admin_profile" in line.lower() or "adminprofile" in line.lower():
        print(f"Line {idx+1}: {line.strip()}")
