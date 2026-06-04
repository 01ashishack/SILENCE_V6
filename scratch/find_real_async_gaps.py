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
        lines = f.readlines()
        
    for idx, line in enumerate(lines):
        cleaned = line.split('//')[0]
        
        # Look for await in the line
        if 'await ' in cleaned:
            # Let's inspect the lines *after* this await
            has_context_after = False
            has_mounted_check_after = False
            found_line_num = -1
            found_content = ''
            
            # Scan up to 5 lines after the await
            for offset in range(1, 6):
                if idx + offset >= len(lines):
                    break
                next_line = lines[idx + offset]
                next_cleaned = next_line.split('//')[0]
                
                # If there is another await, we stop searching
                if 'await ' in next_cleaned:
                    break
                    
                # If there is a mounted check, mark it
                if 'mounted' in next_cleaned:
                    has_mounted_check_after = True
                    
                # Check for context usage in the next line
                for indicator in compiled_indicators:
                    if indicator.search(next_cleaned):
                        # Ensure it's not a print or debug statement
                        if 'print(' in next_cleaned or 'debugPrint(' in next_cleaned:
                            continue
                        has_context_after = True
                        found_line_num = idx + offset + 1
                        found_content = next_line.strip()
                        break
                
                if has_context_after:
                    break
            
            if has_context_after and not has_mounted_check_after:
                real_findings.append({
                    'file': fpath,
                    'await_line': idx + 1,
                    'await_content': line.strip(),
                    'context_line': found_line_num,
                    'context_content': found_content
                })

print(f"Found {len(real_findings)} real async gap context usages without mounted checks:")
for f in real_findings:
    print(f"{f['file']}: line {f['await_line']} (await) -> line {f['context_line']} (context usage): {f['context_content']}")
