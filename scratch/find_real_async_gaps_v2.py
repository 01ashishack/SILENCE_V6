import os
import re

target_files = [
    'lib/screens/reservations/join_flow_screen.dart',
    'lib/screens/reservations/qr_scanner_screen.dart',
    'lib/screens/admin/add_member_wizard.dart',
    'lib/screens/admin/add_member_step1.dart',
    'lib/screens/admin/add_member_step2.dart',
    'lib/screens/admin/add_member_step3.dart',
    'lib/screens/admin/add_member_step4.dart',
    'lib/screens/admin/add_member_step5.dart',
    'lib/screens/library_setup_stage1.dart',
    'lib/screens/library_setup_stage2.dart',
    'lib/screens/library_setup_stage3.dart',
    'lib/screens/admin_profile_complete.dart',
]

context_indicators = [
    r'Navigator\s*\.\s*(?:of|pop|push)',
    r'ScaffoldMessenger\s*\.\s*of',
    r'showDialog\s*\(',
    r'showModalBottomSheet\s*\(',
    r'\bcontext\b',
]

compiled_indicators = [re.compile(ind) for ind in context_indicators]

real_findings = []

for fpath in target_files:
    if not os.path.exists(fpath):
        continue
    
    with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    
    # Let's find all occurrences of 'await '
    # We can split the file content by lines but parse statement completion.
    lines = content.splitlines()
    
    for idx, line in enumerate(lines):
        cleaned = line.split('//')[0]
        if 'await ' in cleaned:
            # We must find where this statement ends.
            # Statement usually ends with a semicolon ';'
            statement_end_idx = idx
            statement_str = cleaned
            
            while ';' not in statement_str and statement_end_idx < len(lines) - 1:
                statement_end_idx += 1
                statement_str += ' ' + lines[statement_end_idx].split('//')[0]
            
            # Now we look at the lines *after* the statement ends (starting at statement_end_idx + 1)
            has_context_after = False
            has_mounted_check_after = False
            found_line_num = -1
            found_content = ''
            
            # Scan up to 5 lines after the statement ends
            for offset in range(1, 6):
                next_line_idx = statement_end_idx + offset
                if next_line_idx >= len(lines):
                    break
                next_line = lines[next_line_idx]
                next_cleaned = next_line.split('//')[0]
                
                # If we hit another await, stop
                if 'await ' in next_cleaned:
                    break
                    
                # If we see a mounted check, mark it
                if 'mounted' in next_cleaned:
                    has_mounted_check_after = True
                    
                # Check for context usage
                for indicator in compiled_indicators:
                    if indicator.search(next_cleaned):
                        if 'print(' in next_cleaned or 'debugPrint(' in next_cleaned:
                            continue
                        has_context_after = True
                        found_line_num = next_line_idx + 1
                        found_content = next_line.strip()
                        break
                        
                if has_context_after:
                    break
            
            if has_context_after and not has_mounted_check_after:
                real_findings.append({
                    'file': fpath,
                    'await_line_start': idx + 1,
                    'statement_end_line': statement_end_idx + 1,
                    'context_line': found_line_num,
                    'context_content': found_content
                })

print(f"Found {len(real_findings)} real async gap context usages:")
for f in real_findings:
    print(f"{f['file']}: await statement (lines {f['await_line_start']}-{f['statement_end_line']}) -> context usage at line {f['context_line']}: {f['context_content']}")
