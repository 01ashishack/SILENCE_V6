import os

path = r"c:\Users\kumar\combined\SILENCE_V6\graphify-out\flat_trans.txt"
out_path = r"c:\Users\kumar\combined\SILENCE_V6\scratch\old_shift_management.dart"

if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # We want to find a block of text in flat_trans.txt where it says:
    # "File Path: `file:///c:/Users/kumar/combined/SILENCE_V6/lib/screens/shift_management.dart`"
    # and "Total Lines: 397"
    # and extract lines 1 to 397.
    
    search_str = "Total Lines: 397"
    idx = content.find(search_str)
    if idx != -1:
        print(f"Found {search_str} at char {idx}")
        # Find the next lines starting with digit: digit:
        lines = content[idx:idx+100000].splitlines()
        extracted_lines = []
        for line in lines:
            if ":" in line:
                parts = line.split(":", 1)
                num_str = parts[0].strip()
                if num_str.isdigit():
                    extracted_lines.append(parts[1])
            if "The above content shows" in line or "The above content does" in line:
                break
        
        with open(out_path, 'w', encoding='utf-8') as out_f:
            out_f.write("\n".join(extracted_lines))
        print("Extracted to", out_path)
    else:
        print("Not found Total Lines: 397")
else:
    print("Log not found")
