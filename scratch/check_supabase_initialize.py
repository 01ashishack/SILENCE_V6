import os

path = r"C:\Users\kumar\AppData\Local\Pub\Cache\hosted\pub.dev\supabase_flutter-2.12.4\lib\src\supabase.dart"
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    for i in range(70, 130):
        if i < len(lines):
            print(f"{i+1}: {lines[i]}", end="")
else:
    print("File not found")
