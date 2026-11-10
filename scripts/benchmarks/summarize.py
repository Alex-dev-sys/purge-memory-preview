#!/usr/bin/env python3
"""Print medians and ranges from an isolated optimization benchmark run."""
import json
from pathlib import Path
import statistics
import sys

work = Path(sys.argv[1])
rows = {}
for label in ['before', 'after']:
    paths = [work / label / 'benchmark-results.jsonl', work / ('cancel-' + label + '.jsonl')]
    rows[label] = [json.loads(line) for path in paths if path.exists() for line in path.read_text().splitlines()]
checksums = [{row['checksum'] for row in data if row['scenario'] == 'memory_groups'} for data in rows.values()]
if any(checksums) and all(checksums) and checksums[0] != checksums[1]:
    raise SystemExit('Memory-group checksums differ between versions')
summary = {}
for scenario in sorted({row['scenario'] for data in rows.values() for row in data}):
    counts = sorted({row.get('count', 0) for data in rows.values() for row in data if row['scenario'] == scenario})
    for count in counts:
        key = scenario + (':' + str(count) if count else '')
        summary[key] = {}
        for label, data in rows.items():
            selected = [row for row in data if row['scenario'] == scenario and row.get('count', 0) == count]
            metrics = {}
            for metric in sorted({k for row in selected for k in row} - {'scenario', 'iteration', 'count'}):
                values = [row[metric] for row in selected if isinstance(row.get(metric), (int, float))]
                if values:
                    metrics[metric] = {'median': statistics.median(values), 'min': min(values), 'max': max(values)}
            summary[key][label] = {'runs': len(selected), 'metrics': metrics}
(work / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
