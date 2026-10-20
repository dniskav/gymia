#!/usr/bin/env python3
"""Validate the authored TrackIA SDD; never claims runtime implementation."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FEATURE = ROOT / 'specs/003-trackia-platform'
errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


required = ['spec.md', 'plan.md', 'research.md', 'data-model.md', 'quickstart.md',
            'tasks.md', 'traceability.md', 'checklists/requirements.md',
            'contracts/assistant-proposals.md', 'contracts/execution.md',
            'contracts/spaces-and-destinations.md', 'contracts/welcome.md']
for name in required:
    check((FEATURE / name).is_file(), f'Missing {name}')
if errors:
    sys.exit('\n'.join(errors))

spec = (FEATURE / 'spec.md').read_text()
tasks = (FEATURE / 'tasks.md').read_text()
trace = (FEATURE / 'traceability.md').read_text()
reqs = re.findall(r'\*\*((?:FR|SC)-\d{3})\*\*:', spec)
expected = [f'FR-{n:03}' for n in range(1, 44)] + [f'SC-{n:03}' for n in range(1, 10)]
check(reqs == expected, 'Expected unique ordered FR-001..043 and SC-001..009')
stories = re.findall(r'^### User Story (\d+) .+\(Priority: (P\d)\)', spec, re.M)
check([int(s) for s, _ in stories] == list(range(1, 10)), 'Expected stories US1..US9')
check(dict(stories) == {str(n): ('P2' if n == 5 else 'P3' if n == 8 else 'P1')
                         for n in range(1, 10)}, 'Unexpected story priorities')
lines = [line for line in tasks.splitlines() if line.startswith('- [')]
pattern = re.compile(r'^- \[ \] (T\d{3})(?: \[P\])?(?: \[US([1-9])\])? .+`[^`]+\.[^`]+`.+\((?:FR|SC)-\d{3}')
ids = []
for line in lines:
    match = pattern.match(line)
    check(bool(match), f'Task format/path/reference invalid: {line[:90]}')
    if match:
        ids.append(match[1])
        check(match[2] is None or match[2] in dict(stories), f'Unknown story: {line[:25]}')
check(ids == [f'T{n:03}' for n in range(1, len(ids)+1)], 'Task IDs not sequential/unique')
check(len(ids) == 63, 'Expected 63 future implementation tasks')
for req in expected:
    row = re.search(r'^\| '+req+r' \|.*$', trace, re.M)
    check(bool(row), f'No traceability row: {req}')
    if row:
        mapped = re.findall(r'T\d{3}', row[0])
        check(bool(mapped) and all(t in ids for t in mapped), f'Invalid mapped tasks: {req}')
        for task_id in mapped:
            task = next((line for line in lines if line.startswith('- [ ] '+task_id+' ')), '')
            check(req in task, f'{req} not referenced by mapped {task_id}')
for cid, sentence in re.findall(r'\| (C\d+) \| (.+?) \|', (FEATURE / 'data-model.md').read_text()):
    check(sentence in tasks, f'Constraint {cid} not quoted verbatim in tasks')

# Restrict checks to authored documents; upstream templates intentionally have slots,
# historical release docs can refer to local-only APK/screenshots described in README.
authored = [FEATURE / name for name in required] + [
    ROOT / '.specify/memory/constitution.md', ROOT / '.specify/UPSTREAM.md',
    ROOT / 'specs/README.md', ROOT / 'specs/00-product/vision.md',
    ROOT / 'specs/00-product/development-plan.md']
for path in authored:
    content = path.read_text()
    check(not re.search(r'NEEDS CLARIFICATION|TKTK|\bTODO\b|\[FEATURE\]|\[DATE\]|\[###', content),
          f'Unresolved placeholder: {path.relative_to(ROOT)}')
    for target in re.findall(r'(?<!!)\[[^\]]+\]\(([^)]+)\)', content):
        if re.match(r'^(?:https?://|mailto:|#)', target):
            continue
        dest = target.split('#', 1)[0]
        check((path.parent / dest).exists(), f'Broken link in {path.relative_to(ROOT)}: {target}')
check('Sync Impact Report' not in (ROOT / '.specify/memory/constitution.md').read_text(),
      'Remove scratch constitution sync report before commit')
check(not (ROOT / '.specify/extensions.yml').exists(),
      'Extensions present: review hooks and update documented provenance')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print('PASS: 9 stories, 43 FR + 9 SC with task coverage, 63 pending tasks, '
      '14 quoted constraints, authored links/placeholders checked. Runtime not tested.')
