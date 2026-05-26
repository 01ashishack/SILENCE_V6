import os
import sys

# Reconfigure stdout to use utf-8 to avoid encoding errors on Windows
try:
    sys.stdout.reconfigure(encoding='utf-8')
except AttributeError:
    pass

log_path = r"C:\Users\kumar\.gemini\antigravity\brain\38348a3d-f5e4-4b11-8fd8-ac03399ed288\.system_generated\logs\transcript.jsonl"

if not os.path.exists(log_path):
    print(f"Log path does not exist: {log_path}")
    sys.exit(1)

print("Searching transcript.jsonl...", flush=True)

with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
    for i, line in enumerate(f):
        line_lower = line.lower()
        if "password" in line_lower and "psycopg2" not in line_lower and "passwords = [" not in line_lower:
            idx = line_lower.find("password")
            start = max(0, idx - 100)
            end = min(len(line), idx + 200)
            # Safe print
            snippet = line[start:end].replace('\n', ' ').strip()
            print(f"Line {i+1}: ... {snippet} ...", flush=True)
