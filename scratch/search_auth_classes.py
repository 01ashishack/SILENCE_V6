import os

pkg_dir = r"C:\Users\kumar\AppData\Local\Pub\Cache\hosted\pub.dev\supabase_flutter-2.12.4\lib\src"

for root, dirs, files in os.walk(pkg_dir):
    for file in files:
        if file.endswith('.dart'):
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            if 'class FlutterAuthClientOptions' in content or 'EmptyLocalStorage' in content:
                print(f"File: {path}")
                # Print class definition snippet
                lines = content.splitlines()
                for idx, line in enumerate(lines):
                    if 'class FlutterAuthClientOptions' in line or 'class EmptyLocalStorage' in line:
                        for j in range(max(0, idx-2), min(len(lines), idx+30)):
                            print(f"  {j+1}: {lines[j]}")
