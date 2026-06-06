import os
import re
import csv

def find_screens(root_dir):
    screens = []
    screens_dir = os.path.join(root_dir, 'lib', 'screens')
    for dirpath, _, filenames in os.walk(screens_dir):
        for file in filenames:
            if file.endswith('.dart'):
                full_path = os.path.join(dirpath, file)
                rel_path = os.path.relpath(full_path, root_dir)
                
                with open(full_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    
                # Find all classes extending StatefulWidget or StatelessWidget
                classes = re.findall(r'class\s+(\w+)\s+extends\s+(StatefulWidget|StatelessWidget|ConsumerStatefulWidget|ConsumerWidget)', content)
                for class_name, _ in classes:
                    # Skip private classes
                    if class_name.startswith('_'):
                        continue
                    screens.append({
                        'class': class_name,
                        'file': rel_path.replace('\\', '/'),
                    })
    return screens

def parse_routes(root_dir):
    main_path = os.path.join(root_dir, 'lib', 'main.dart')
    with open(main_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Simple regex search for routes map
    # e.g., '/admin/home': (context) => const AdminHomeScreen(),
    routes_match = re.search(r'routes:\s*\{([^}]+)\}', content)
    routes = {}
    if routes_match:
        routes_block = routes_match.group(1)
        # Find all routes
        for line in routes_block.split('\n'):
            line = line.strip()
            # match "'/route': (context) => const ScreenClass()," or similar
            m = re.match(r"['\"]([^'\"]+)['\"]\s*:\s*\(context\)\s*(?:=>|\{)\s*(?:const\s+)?(\w+)", line)
            if m:
                routes[m.group(2)] = m.group(1)
    return routes

def main():
    root_dir = 'c:/Users/kumar/combined/SILENCE_V6'
    screens = find_screens(root_dir)
    routes = parse_routes(root_dir)
    
    # Read original screen inventory
    orig_path = os.path.join(root_dir, 'silence_app', '15_Screen_Inventory.csv')
    orig_screens = {}
    if os.path.exists(orig_path):
        with open(orig_path, 'r', encoding='utf-8') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                if row['Screen Name']:
                    orig_screens[row['Screen Name']] = row
                    
    # Combine data
    updated_inventory = []
    
    # We want to identify the role: Admin, Member, or Both
    for s in screens:
        class_name = s['class']
        file_path = s['file']
        route = routes.get(class_name, 'N/A')
        
        # Determine role from folder/name
        if 'admin' in file_path.lower():
            role = 'Admin'
        elif 'member' in file_path.lower():
            role = 'Member'
        elif class_name in ['ExploreScreen', 'LibraryPublicProfileScreen', 'LibraryQueryScreen', 'RenewalScreen', 'PastLibraryDetailScreen']:
            role = 'Member'
        elif class_name in ['SocialLinksEditScreen', 'AboutUsScreen', 'HelpSupportScreen', 'TermsScreen', 'AppSettingsScreen', 'VerifiedBadgeScreen', 'ShiftManagementScreen', 'PricingPlansScreen', 'BusinessRulesScreen', 'BrandingAssetsScreen', 'QRAssetsScreen', 'AddonServicesScreen', 'NotificationPreferencesScreen', 'ExportCenterScreen', 'SubscriptionScreen', 'AuditLogScreen', 'ReferralSettingsScreen', 'ScheduledClosuresScreen', 'AnnouncementsHistoryScreen']:
            role = 'Admin'
        else:
            role = 'Both'
            
        # Determine Status: implemented, partial, broken
        # From our audit, we know:
        # - requests_sub_tab.dart (RequestsSubTab) has a broken database notification insert
        # - library_setup_stage2.dart (LibrarySetupStage2Screen) has a data-loss cascade delete
        # - join_flow_screen.dart (JoinFlowScreen) has a public upload risk (partial/broken)
        # - member_explore_screen.dart (ExploreScreen) has a broken notifications route click
        # - payment_setup.dart (PaymentSetupScreen) is orphaned (partial/orphaned)
        # - subscription_screen.dart (SubscriptionScreen) has simulated payments (partial)
        # - export_center.dart (ExportCenterScreen) has plain text pdf and no excel (partial)
        status = 'implemented'
        if class_name in ['RequestsSubTab', 'LibrarySetupStage2Screen', 'ExploreScreen']:
            status = 'broken'
        elif class_name in ['JoinFlowScreen', 'PaymentSetupScreen', 'SubscriptionScreen', 'ExportCenterScreen']:
            status = 'partial'
            
        was_documented = class_name in orig_screens
        notes = ''
        if not was_documented:
            notes = 'New screen (exists in code but not documented)'
        elif orig_screens[class_name]['File Path'].replace('\\', '/') != file_path:
            notes = f"Renamed/moved (original path: {orig_screens[class_name]['File Path']})"
            
        updated_inventory.append({
            'Screen Name': class_name,
            'File Path': file_path,
            'Route': route,
            'Role': role,
            'Status': status,
            'Documented in Original': 'Yes' if was_documented else 'No',
            'Notes': notes
        })
        
    # Check for documented screens that no longer exist
    all_screen_names = {s['class'] for s in screens}
    for orig_name, orig_data in orig_screens.items():
        if orig_name not in all_screen_names and orig_name not in ['SilenceApp', '_CalendarDialogPicker', 'QRModal', 'SeatGenerationInlineWidget', 'VacantSeatGrid']:
            # These are helper classes or entry points, let's check if they exist anywhere
            updated_inventory.append({
                'Screen Name': orig_name,
                'File Path': orig_data['File Path'],
                'Route': 'N/A',
                'Role': orig_data['Role'],
                'Status': 'removed',
                'Documented in Original': 'Yes',
                'Notes': 'Documented screen does not exist in code'
            })
            
    # Output CSV
    out_csv = os.path.join(root_dir, 'docs_audit', 'UPDATED_Screen_Inventory.csv')
    with open(out_csv, 'w', newline='', encoding='utf-8') as csvfile:
        fieldnames = ['Screen Name', 'File Path', 'Route', 'Role', 'Status', 'Documented in Original', 'Notes']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for row in updated_inventory:
            writer.writerow(row)
            
    print(f"Generated {out_csv} with {len(updated_inventory)} records.")

if __name__ == '__main__':
    main()
