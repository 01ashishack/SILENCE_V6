import json

log_path = r"C:\Users\kumar\.gemini\antigravity\brain\37d55273-7dc4-41df-a50a-98429ca188df\.system_generated\logs\transcript.jsonl"

print("Searching transcript.jsonl for all actions on member_history_tab.dart...")

with open(log_path, 'r', encoding='utf-8') as f:
    for line in f:
        try:
            data = json.loads(line)
            tool_calls = data.get('tool_calls', [])
            for call in tool_calls:
                name = call.get('name', '')
                args = call.get('arguments', {}) or call.get('args', {})
                target = args.get('TargetFile', '') or args.get('TargetFile', '')
                if 'member_history_tab.dart' in target:
                    code_len = 0
                    if 'CodeContent' in args:
                        code_len = len(args['CodeContent'])
                    elif 'ReplacementContent' in args:
                        code_len = len(args['ReplacementContent'])
                    elif 'ReplacementChunks' in args:
                        code_len = sum(len(c.get('ReplacementContent', '')) for c in args['ReplacementChunks'])
                    print(f"Step {data.get('step_index')}: {name}, target={target}, len={code_len}")
        except Exception as e:
            pass
