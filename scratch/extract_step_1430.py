import json

log_path = r"C:\Users\kumar\.gemini\antigravity\brain\37d55273-7dc4-41df-a50a-98429ca188df\.system_generated\logs\transcript.jsonl"
out_path = r"c:\Users\kumar\combined\SILENCE_V6\scratch\step_1430_raw.txt"

with open(log_path, 'r', encoding='utf-8') as f:
    for line in f:
        try:
            data = json.loads(line)
            if data.get('step_index') == 1430:
                with open(out_path, 'w', encoding='utf-8') as out_f:
                    json.dump(data, out_f, indent=2)
                print("Wrote Step 1430 raw data to scratch/step_1430_raw.txt")
        except Exception as e:
            pass
