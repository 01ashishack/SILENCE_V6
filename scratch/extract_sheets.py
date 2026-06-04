import os

path = r"c:\Users\kumar\combined\SILENCE_V6\graphify-out\flat_trans.txt"
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Let's search for _showEditShiftSheet and print the lines around it
    lines = content.splitlines()
    for idx, line in enumerate(lines):
        if 'void _showEditShiftSheet' in line:
            print("FOUND _showEditShiftSheet at line:", idx)
            for j in range(max(0, idx-5), min(len(lines), idx+150)):
                print(lines[j])
            break
else:
    print("Log not found")
