import os

file_path = r"c:\Users\kumar\combined\SILENCE_V6\lib\screens\admin_analytics_tab.dart"

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.splitlines()

depth = 0
in_class = False
class_start_line = -1

for idx, line in enumerate(lines):
    line_num = idx + 1
    if line_num == 865:
        # Skip the extra brace at line 865
        continue
    
    clean_line = line.split('//')[0]
    opens = clean_line.count('{')
    closes = clean_line.count('}')
    
    prev_depth = depth
    depth += opens - closes
    
    if "class _AdminAnalyticsTabState" in clean_line:
        in_class = True
        class_start_line = line_num
        print(f"Class starts at line {line_num}, depth before: {prev_depth}")
        
    if in_class:
        if depth == 0 and prev_depth > 0:
            print(f"Class matching brace found at line {line_num}, clean_line: {clean_line.strip()}")
            in_class = False

print(f"Final depth: {depth}")
