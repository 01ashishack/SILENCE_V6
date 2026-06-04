import os
import re

pattern = re.compile(r'(\b\w+|\)|\])\s*\!(?!=)')

suspicious_keywords = [
    r'\[[^\]]+\]\s*\!',       # Map/List index followed by ! e.g. map['key']!
    r'arguments\s*\!',        # ModalRoute arguments followed by !
    r'settings\s*\!',         # settings followed by !
    r'currentUser\s*\!',      # Supabase currentUser!
    r'auth\s*\.currentUser\s*\!', # auth.currentUser!
    r'email\s*\!',            # email!
    r'phone\s*\!',            # phone!
    r'userData\s*\!',         # userData!
    r'payload\s*\!',          # payload!
    r'json\s*\!',             # json!
    r'data\s*\!',             # data!
]

compiled_suspicious = [re.compile(k) for k in suspicious_keywords]

dart_files = []
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            dart_files.append(os.path.join(root, f))

findings = []
for fpath in sorted(dart_files):
    rel_path = os.path.relpath(fpath, 'lib')
    with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
        for idx, line in enumerate(f, 1):
            cleaned = line.split('//')[0]
            cleaned = re.sub(r'"[^"\\]*(?:\\.[^"\\]*)*"', '""', cleaned)
            cleaned = re.sub(r"'[^'\\]*(?:\\.[^'\\]*)*'", "''", cleaned)
            
            # Find if there is a postfix null assertion
            has_bang = False
            for match in pattern.finditer(cleaned):
                start = match.start()
                matched_text = match.group(0)
                after_idx = start + len(matched_text)
                if after_idx < len(cleaned) and cleaned[after_idx] == '=':
                    continue
                has_bang = True
                break
                
            if has_bang:
                # Check if it is suspicious
                is_suspicious = False
                for pattern_susp in compiled_suspicious:
                    if pattern_susp.search(cleaned):
                        is_suspicious = True
                        break
                
                # Check for cast + bang, e.g. as String?! or as Map!
                if 'as ' in cleaned and '!' in cleaned:
                    is_suspicious = True
                
                if is_suspicious:
                    findings.append({
                        'file': rel_path,
                        'line': idx,
                        'content': line.strip()
                    })

print(f"Found {len(findings)} suspicious null assertions.")
for f in findings[:150]:
    print(f"{f['file']}:{f['line']}: {f['content']}")
