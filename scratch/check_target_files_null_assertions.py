import os
import re

files_to_check = [
    'lib/screens/admin/add_member_wizard.dart',
    'lib/screens/member_profile_edit.dart',
    'lib/screens/reservations/member_detail_screen.dart',
    'lib/screens/reservations/qr_scanner_screen.dart',
    'lib/screens/reservations/layout_sub_tab.dart',
    'lib/screens/shift_management.dart'
]

pattern = re.compile(r'(\b\w+|\)|\])\s*\!(?!=)')

for fpath in files_to_check:
    print('='*80)
    print(f'FILE: {fpath}')
    if not os.path.exists(fpath):
        print('FILE NOT FOUND')
        continue
    with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
        for idx, line in enumerate(f, 1):
            cleaned = line.split('//')[0]
            cleaned = re.sub(r'"[^"\\]*(?:\\.[^"\\]*)*"', '""', cleaned)
            cleaned = re.sub(r"'[^'\\]*(?:\\.[^'\\]*)*'", "''", cleaned)
            for match in pattern.finditer(cleaned):
                start = match.start()
                matched_text = match.group(0)
                after_idx = start + len(matched_text)
                if after_idx < len(cleaned) and cleaned[after_idx] == '=':
                    continue
                print(f'  Line {idx}: {line.strip()}')
