import re

src_path = r"c:\Users\kumar\combined\SILENCE_V6\lib\screens\member_history_tab_phase1.dart"
dest_path = r"c:\Users\kumar\combined\SILENCE_V6\scratch\member_history_tab_phase1_decoded.dart"

with open(src_path, 'r', encoding='utf-8') as f:
    content = f.read().strip()

# Strip leading and trailing double quotes if present
if content.startswith('"') and content.endswith('"'):
    content = content[1:-1]

# Now, we want to replace escaped newlines with actual newlines, and other escapes
# e.g., \n -> newline, \" -> ", \' -> ', \\ -> \
# We can use codecs.decode on bytes, or do a regex replacement.
# Let's do it using bytes decode:
try:
    decoded = bytes(content, "utf-8").decode("unicode_escape")
except Exception as e:
    print("unicode_escape failed, falling back to manual replacement:", e)
    # Manual unescaping fallback
    decoded = content.replace('\\n', '\n').replace('\\"', '"').replace("\\'", "'").replace('\\\\', '\\')

with open(dest_path, 'w', encoding='utf-8') as f:
    f.write(decoded)

print("Decoded content successfully written to scratch/member_history_tab_phase1_decoded.dart")
