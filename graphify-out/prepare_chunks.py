import json
from pathlib import Path

detect = json.loads(Path("graphify-out/.graphify_detect.json").read_text())
code_files = set(detect.get("files", {}).get("code", []))
lines = [l.strip() for l in Path("graphify-out/.graphify_uncached.txt").read_text().splitlines() if l.strip()]
non_code = [l for l in lines if l not in code_files]

chunk_size = 21
chunks = [non_code[i:i+chunk_size] for i in range(0, len(non_code), chunk_size)]
for i, chunk in enumerate(chunks):
    Path(f"graphify-out/.graphify_chunk_files_{i+1}.txt").write_text("\n".join(chunk))
    print(f"Chunk {i+1}: {len(chunk)} files")
print(f"Total chunks: {len(chunks)}")
