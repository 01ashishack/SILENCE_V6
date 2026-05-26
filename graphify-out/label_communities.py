import sys, json, re
from collections import Counter
from pathlib import Path
from graphify.build import build_from_json
from graphify.cluster import score_all
from graphify.analyze import god_nodes, surprising_connections, suggest_questions
from graphify.report import generate

extraction = json.loads(Path('graphify-out/.graphify_extract.json').read_text(encoding='utf-8'))
detection  = json.loads(Path('graphify-out/.graphify_detect.json').read_text(encoding='utf-8'))
analysis   = json.loads(Path('graphify-out/.graphify_analysis.json').read_text(encoding='utf-8'))

G = build_from_json(extraction)
communities = {int(k): v for k, v in analysis['communities'].items()}
cohesion = {int(k): v for k, v in analysis['cohesion'].items()}
tokens = {'input': extraction.get('input_tokens', 0), 'output': extraction.get('output_tokens', 0)}

# Generate labels automatically based on node labels
labels = {}
for cid, members in communities.items():
    words = []
    for nid in members:
        label = G.nodes[nid].get('label', nid)
        # Split by non-alphanumeric
        parts = re.split(r'[^a-zA-Z0-9]+', label)
        words.extend([p for p in parts if len(p) > 2 and p.lower() not in ('the', 'and', 'for', 'with', 'from', 'get', 'set')])
    if words:
        most_common = [w[0] for w in Counter(words).most_common(3)]
        labels[cid] = ' '.join(most_common).title()
    else:
        labels[cid] = f'Community {cid}'

questions = suggest_questions(G, communities, labels)

report = generate(G, communities, cohesion, labels, analysis['gods'], analysis['surprises'], detection, tokens, '.', suggested_questions=questions)
Path('graphify-out/GRAPH_REPORT.md').write_text(report, encoding='utf-8')
Path('graphify-out/.graphify_labels.json').write_text(json.dumps({str(k): v for k, v in labels.items()}), encoding='utf-8')
print('Report updated with community labels')
