import os

pkg_dir = r"C:\Users\kumar\AppData\Local\Pub\Cache\hosted\pub.dev\supabase_flutter-2.12.4\lib\src"

for root, dirs, files in os.walk(pkg_dir):
    for file in files:
        if file.endswith('.dart'):
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            if 'GotrueAsyncStorage' in content:
                print(f"File: {path}")
                # Print lines containing GotrueAsyncStorage
                lines = content.splitlines()
                for idx, line in enumerate(lines):
                    if 'GotrueAsyncStorage' in line:
                        print(f"  {idx+1}: {line}")
