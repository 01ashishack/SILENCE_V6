import os
import re
import sys

# Set stdout to UTF-8
sys.stdout.reconfigure(encoding='utf-8')

# Regular expression to match Dart postfix null assertion operator '!'
# It matches identifiers, function calls, or list accesses ending with '!' but not '!=' or '!' in strings/comments.
pattern = re.compile(r'(\b\w+|\)|\])\s*\!(?!=)')

dart_files = []
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            dart_files.append(os.path.join(root, f))

# We'll ignore common comments and string literals to reduce noise
def clean_line_comments_and_strings(line):
    # Remove single-line comments
    if '//' in line:
        line = line.split('//')[0]
    # Remove string literals
    line = re.sub(r'"[^"\\]*(?:\\.[^"\\]*)*"', '""', line)
    line = re.sub(r"'[^'\\]*(?:\\.[^'\\]*)*'", "''", line)
    return line

results = []
for fpath in sorted(dart_files):
    rel_path = os.path.relpath(fpath, 'lib')
    with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
        for idx, line in enumerate(f, 1):
            cleaned = clean_line_comments_and_strings(line)
            for match in pattern.finditer(cleaned):
                # Double check to ensure it's not a logical negation at the start of a token
                # e.g., if (!condition)
                start = match.start()
                matched_text = match.group(0)
                
                # Check if it is !=
                after_idx = start + len(matched_text)
                if after_idx < len(cleaned) and cleaned[after_idx] == '=':
                    continue
                    
                results.append({
                    'file': rel_path,
                    'line': idx,
                    'content': line.strip()
                })

# Write findings to a text file
out_path = 'scratch/null_assertion_audit.txt'
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w', encoding='utf-8') as out_f:
    out_f.write(f"Total postfix null assertions found: {len(results)}\n\n")
    for r in results:
        out_f.write(f"{r['file']}:{r['line']}: {r['content']}\n")

print(f"Audit written successfully to {out_path}. Total: {len(results)} matches.")
