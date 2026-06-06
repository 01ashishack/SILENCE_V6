import os

assets_dir = r"c:\Users\kumar\combined\SILENCE_V6\assets\images"
if os.path.exists(assets_dir):
    print("Files in assets/images:")
    for f in os.listdir(assets_dir):
        print(" -", f)
else:
    print("assets/images directory not found")
