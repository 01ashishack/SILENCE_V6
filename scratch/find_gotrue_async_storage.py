import os

pkg_dir = r"C:\Users\kumar\AppData\Local\Pub\Cache\hosted\pub.dev"

found = False
for root, dirs, files in os.walk(pkg_dir):
    if found:
        break
    for file in files:
        if file.endswith('.dart'):
            path = os.path.join(root, file)
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                if 'class GotrueAsyncStorage' in content:
                    print(f"File: {path}")
                    lines = content.splitlines()
                    for idx, line in enumerate(lines):
                        if 'class GotrueAsyncStorage' in line:
                            for j in range(max(0, idx-2), min(len(lines), idx+20)):
                                print(f"  {j+1}: {lines[j]}")
                            found = True
                            break
            except Exception:
                pass
