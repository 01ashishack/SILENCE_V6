import json

log_path = r"C:\Users\kumar\.gemini\antigravity\brain\37d55273-7dc4-41df-a50a-98429ca188df\.system_generated\logs\transcript.jsonl"
out_path = r"c:\Users\kumar\combined\SILENCE_V6\scratch\spec.md"

with open(log_path, 'r', encoding='utf-8') as f:
    for line in f:
        try:
            data = json.loads(line)
            if data.get('step_index') == 1178:
                content = data.get('content', '')
                with open(out_path, 'w', encoding='utf-8') as out_f:
                    out_f.write(content)
                print("Successfully wrote spec to scratch/spec.md")
        except Exception as e:
            pass
