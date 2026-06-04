import os
import re

path = r"c:\Users\kumar\combined\SILENCE_V6\graphify-out\flat_trans.txt"
out_path = r"c:\Users\kumar\combined\SILENCE_V6\scratch\old_shift_management.dart"

if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # We want to find the first/best block where shift_management.dart is displayed.
    # Look for: "File Path: `file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/shift_management.dart`"
    # and "Total Lines: 397"
    pattern = r"File Path: `file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/shift_management.dart`[\s\S]*?Total Lines: 397"
    matches = list(re.finditer(pattern, content))
    if matches:
        start_idx = matches[0].end()
        # Find the next 397 lines starting with a number followed by a colon.
        lines = content[start_idx:start_idx+150000].splitlines()
        extracted = {}
        for line in lines:
            # We match something like "  145: code" or "145: code"
            m = re.match(r"^\s*(\d+):\s*(.*)", line)
            if m:
                line_num = int(m.group(1))
                code = m.group(2)
                extracted[line_num] = code
            elif "The above content shows" in line or "The above content does" in line:
                if len(extracted) > 50:
                    break
        
        # Sort and write
        sorted_keys = sorted(extracted.keys())
        output_code = [extracted[k] for k in sorted_keys]
        
        with open(out_path, 'w', encoding='utf-8') as out_f:
            out_f.write("\n".join(output_code))
        print(f"Extracted {len(output_code)} lines to {out_path}")
    else:
        print("Pattern not found")
else:
    print("Log not found")
