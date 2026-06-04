import os
import re

log_path = r"C:\Users\kumar\.gemini\antigravity\brain\38348a3d-f5e4-4b11-8fd8-ac03399ed288\.system_generated\tasks\task-10898.log"

errors = []
warnings = []
infos = []

if os.path.exists(log_path):
    with open(log_path, 'r', encoding='utf-8') as f:
        for line in f:
            line_strip = line.strip()
            if not line_strip:
                continue
            # Typical formats:
            # error - ...
            # warning - ...
            #    info - ...
            if line_strip.startswith('error -'):
                errors.append(line_strip)
            elif line_strip.startswith('warning -'):
                warnings.append(line_strip)
            elif line_strip.startswith('info -'):
                infos.append(line_strip)
            elif ' - ' in line_strip and ('warning ' in line_strip or 'error ' in line_strip or 'info ' in line_strip):
                # check spaces
                if 'error' in line_strip.split(' - ')[0]:
                    errors.append(line_strip)
                elif 'warning' in line_strip.split(' - ')[0]:
                    warnings.append(line_strip)
                elif 'info' in line_strip.split(' - ')[0]:
                    infos.append(line_strip)

print(f"Errors found: {len(errors)}")
print(f"Warnings found: {len(warnings)}")
print(f"Infos found: {len(infos)}")

# Let's save a summary to a file
with open('scratch/analyze_summary.txt', 'w', encoding='utf-8') as sf:
    sf.write(f"Errors ({len(errors)}):\n")
    for e in errors:
        sf.write(f"- {e}\n")
    sf.write(f"\nWarnings ({len(warnings)}):\n")
    for w in warnings:
        sf.write(f"- {w}\n")
    sf.write(f"\nInfos ({len(infos)}):\n")
    for i in infos:
        sf.write(f"- {i}\n")
