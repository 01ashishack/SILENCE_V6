import os

log_path = r"C:\Users\kumar\.gemini\antigravity\brain\38348a3d-f5e4-4b11-8fd8-ac03399ed288\.system_generated\tasks\task-10898.log"

findings = {}

if os.path.exists(log_path):
    with open(log_path, 'r', encoding='utf-8') as f:
        for line in f:
            if 'use_build_context_synchronously' in line:
                # Example:
                #    info - Don't use 'BuildContext's across async gaps - lib\core\offline_sync.dart:21:26 - use_build_context_synchronously
                parts = line.strip().split(' - ')
                if len(parts) >= 3:
                    msg = parts[1]
                    location = parts[2]
                    loc_parts = location.split(':')
                    if len(loc_parts) >= 2:
                        fpath = loc_parts[0].replace('lib\\', '')
                        line_num = loc_parts[1]
                        
                        if fpath not in findings:
                            findings[fpath] = []
                        findings[fpath].append((line_num, msg))

for fpath, items in sorted(findings.items()):
    print(f"File: {fpath}")
    for item in items:
        print(f"  Line {item[0]}: {item[1]}")
