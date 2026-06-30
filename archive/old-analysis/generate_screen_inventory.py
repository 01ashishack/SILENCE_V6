import os
import re
import csv

def find_dart_files(root_dir):
    """Recursively find all .dart files in lib/ excluding certain folders."""
    dart_files = []
    lib_dir = os.path.join(root_dir, 'lib')
    if not os.path.exists(lib_dir):
        print("❌ lib directory not found. Make sure you are in the Flutter project root.")
        return dart_files
    for dirpath, _, filenames in os.walk(lib_dir):
        # Skip widget, model, service, core folders (adjust as needed)
        if any(skip in dirpath for skip in ['/widgets/', '/models/', '/services/', '/core/']):
            continue
        for file in filenames:
            if file.endswith('.dart'):
                full_path = os.path.join(dirpath, file)
                rel_path = os.path.relpath(full_path, root_dir)
                dart_files.append(rel_path)
    return dart_files

def extract_widget_class(content):
    """Extract class name that extends StatefulWidget or StatelessWidget."""
    pattern = r'class\s+(\w+)\s+extends\s+(StatefulWidget|StatelessWidget)'
    match = re.search(pattern, content)
    if match:
        return match.group(1)
    return None

def infer_role(file_path):
    """Infer role from file path (Admin/Member/Both)."""
    if 'admin' in file_path.lower():
        return 'Admin'
    elif 'member' in file_path.lower():
        return 'Member'
    else:
        return 'Both'

def main():
    # Ask for project root path or use current directory
    project_root = input("Enter Flutter project root path (or press Enter for current directory): ").strip()
    if not project_root:
        project_root = os.getcwd()
    if not os.path.exists(os.path.join(project_root, 'lib')):
        print("❌ Invalid path: 'lib' folder not found.")
        return
    
    print(f"Scanning {project_root} ...")
    dart_files = find_dart_files(project_root)
    print(f"Found {len(dart_files)} Dart files.")
    
    inventory = []
    for rel_path in dart_files:
        full_path = os.path.join(project_root, rel_path)
        try:
            with open(full_path, 'r', encoding='utf-8') as f:
                content = f.read()
                class_name = extract_widget_class(content)
                if class_name:
                    role = infer_role(rel_path)
                    inventory.append({
                        'Screen Name': class_name,
                        'File Path': rel_path,
                        'Role': role,
                        'Description': '',
                        'Navigated From': '',
                        'Stack/Modal/Tab': ''
                    })
        except Exception as e:
            print(f"⚠️ Error reading {rel_path}: {e}")
    
    # Write CSV
    output_file = 'screen_inventory.csv'
    with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
        fieldnames = ['Screen Name', 'File Path', 'Role', 'Description', 'Navigated From', 'Stack/Modal/Tab']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for row in inventory:
            writer.writerow(row)
    
    print(f"✅ Generated {output_file} with {len(inventory)} screens.")
    print("Copy this file to silence_app/15_Screen_Inventory.csv (overwrite existing).")

if __name__ == '__main__':
    main()