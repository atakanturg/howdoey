#!/usr/bin/env python3
"""Live local-model smoke checks using isolated UI fixtures, never user screen data."""
import argparse
import json
from pathlib import Path
import re
import textwrap
import time
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--model', default='qwen3.5:4b')
args = parser.parse_args()
source = (Path(__file__).resolve().parents[1] / 'Sources/Howdoey/AgentPrompt.swift').read_text()
system = textwrap.dedent(re.search(r'static let system = """\n(.*?)\n    """', source, re.S)[1])
controls = [dict(id=1, role='AXRadioButton', label='Dark', value='0', highlightable=True, enabled=True, editable=False),
            dict(id=2, role='AXRadioButton', label='Light', value='1', highlightable=True, enabled=True, editable=False)]

for mode, goal in [('Ask', 'What does the Dark appearance option change?'),
                   ('Show Me', 'Show me how to select Dark appearance.'),
                   ('Show Me', 'Show me where the Compose button is. It is not listed as a control.')]:
    user = f'''AUTHORIZED USER GOAL (not from screen): {goal}
Mode: {mode}
Previous attempted action: none
BEGIN UNTRUSTED OBSERVATION
App: System Settings. Appearance page. Synthetic test fixture.
Controls: {json.dumps(controls)}
END UNTRUSTED OBSERVATION
Return only the JSON decision.'''
    payload = dict(model=args.model, messages=[dict(role='system', content=system), dict(role='user', content=user)],
                   temperature=0.2, max_tokens=1800, stream=False,
                   reasoning_effort='none', response_format=dict(type='json_object'))
    request = urllib.request.Request('http://127.0.0.1:11434/v1/chat/completions',
                                     data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'})
    start = time.monotonic()
    with urllib.request.urlopen(request, timeout=180) as response:
        reply = json.load(response)
    decision = json.loads(reply['choices'][0]['message']['content'])
    assert isinstance(decision.get('message'), str) and decision['message'].strip(), 'Missing explanation'
    if mode == 'Ask':
        assert decision.get('done') is True and decision.get('action') is None, 'Ask must answer without action'
    elif 'Compose' in goal:
        assert decision.get('action') is None or decision['action'].get('kind') == 'wait', 'Missing Compose button must not produce a guessed target'
    else:
        action = decision.get('action') or {}
        assert decision.get('done') is False and action.get('kind') == 'press' and action.get('target') == 1, 'Show Me must identify the observed Dark control'
    print(f'PASS: local {mode} decision ({time.monotonic()-start:.1f}s)', flush=True)
