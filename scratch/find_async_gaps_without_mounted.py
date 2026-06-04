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

# We want to parse each file and find await statements, and then scan the next few lines
# for Context usage (Navigator, ScaffoldMessenger, context, etc.)
# and check if there is a 'mounted' check between the await and the context usage.

findings = []

context_indicators = [
    r'Navigator\s*\.\s*(?:of|pop|push)',
    r'ScaffoldMessenger\s*\.\s*of',
    r'showDialog\s*\(',
    r'showModalBottomSheet\s*\(',
    r'\bcontext\b',
]

compiled_indicators = [re.compile(ind) for ind in context_indicators]

for fpath in target_files:
    if not os.path.exists(fpath):
        continue
    
    with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
        
    idx = 0
    while idx < len(lines):
        line = lines[idx]
        cleaned = line.split('//')[0]
        
        # Check if line contains an 'await'
        if 'await ' in cleaned:
            # Let's inspect the next 5 lines for BuildContext usage
            has_context_usage = False
            has_mounted_check = False
            usage_line_idx = -1
            usage_text = ''
            
            for offset in range(1, 8):
                if idx + offset >= len(lines):
                    break
                next_line = lines[idx + offset]
                next_cleaned = next_line.split('//')[0]
                
                # If there's another await, we stop searching further to avoid overlap
                if 'await ' in next_cleaned and offset > 1:
                    break
                    
                # Check for mounted check
                if 'mounted' in next_cleaned:
                    has_mounted_check = True
                    
                # Check for BuildContext usage
                for indicator in compiled_indicators:
                    if indicator.search(next_cleaned):
                        has_context_usage = True
                        usage_line_idx = idx + offset + 1
                        usage_text = next_line.strip()
                        break
                
                if has_context_usage and not has_mounted_check:
                    # Found context usage without a mounted check in the path
                    findings.append({
                        'file': fpath,
                        'await_line': idx + 1,
                        'await_content': line.strip(),
                        'usage_line': usage_line_idx,
                        'usage_content': usage_text
                    })
                    break # Only report first issue per await
                    
        idx += 1

print(f"Found {len(findings)} potential context async gaps without mounted checks.")
for f in findings:
    print(f"{f['file']}: await at line {f['await_line']} followed by context usage at line {f['usage_line']}: {f['usage_content']}")
