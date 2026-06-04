import os
import re

path = r"c:\Users\kumar\combined\SILENCE_V6\graphify-out\flat_trans.txt"
out_path = r"c:\Users\kumar\combined\SILENCE_V6\scratch\old_shift_management_full.dart"

if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # We want to find: "File Path: `file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/shift_management.dart`"
    # and "Total Lines: 397"
    # Let's find the start position
    start_pos = -1
    for match in re.finditer(r"File Path: `file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/shift_management\.dart`", content):
        sub_content = content[match.start():match.start()+1000]
        if "Total Lines: 397" in sub_content:
            start_pos = match.start()
            break
            
    if start_pos != -1:
        print(f"Found file section at char {start_pos}")
        lines = content[start_pos:start_pos+300000].splitlines()
        extracted = {}
        for line in lines:
            m = re.match(r"^\s*(\d+):\s*(.*)", line)
            if m:
                line_num = int(m.group(1))
                code = m.group(2)
                extracted[line_num] = code
            elif "The above content shows the entire" in line:
                break
        
        # Build full file
        full_code = []
        for i in range(1, 398):
            if i in extracted:
                full_code.append(extracted[i])
            else:
                full_code.append(f"// MISSING LINE {i}")
        
        with open(out_path, 'w', encoding='utf-8') as out_f:
            out_f.write("\n".join(full_code))
        print(f"Saved {len(full_code)} lines (with {full_code.count('// MISSING LINE ')} missing lines) to {out_path}")
    else:
        print("Required file section not found")
else:
    print("Log file not found")
