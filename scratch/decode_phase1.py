import json
import ast

src_path = r"c:\Users\kumar\combined\SILENCE_V6\lib\screens\member_history_tab_phase1.dart"
dest_path = r"c:\Users\kumar\combined\SILENCE_V6\scratch\member_history_tab_phase1_decoded.dart"

with open(src_path, 'r', encoding='utf-8') as f:
    content = f.read().strip()

# Let's try parsing it as a JSON string, or using ast.literal_eval if it's a quoted string
try:
    if content.startswith('"') and content.endswith('"'):
        decoded = json.loads(content)
    else:
        # Fallback to ast.literal_eval or just JSON loads if it's double-quoted string
        decoded = json.loads('"' + content.replace('"', '\\"') + '"')
except Exception as e:
    try:
        decoded = ast.literal_eval(content)
    except Exception as e2:
        print("Failed to decode using JSON/AST:", e, e2)
        decoded = content

with open(dest_path, 'w', encoding='utf-8') as f:
    f.write(decoded)

print("Decoded content written to scratch/member_history_tab_phase1_decoded.dart")
