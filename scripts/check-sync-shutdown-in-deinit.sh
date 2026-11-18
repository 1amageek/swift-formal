#!/bin/sh
exec python3 - "$@" <<'PY'
from pathlib import Path
import re,sys
errors=[]
for arg in sys.argv[1:] or ['Sources','Tests']:
 for path in Path(arg).rglob('*.swift'):
  source=path.read_text()
  for match in re.finditer(r'\bdeinit\s*\{',source):
   end=match.end();depth=1
   while end<len(source) and depth:
    depth += (source[end]=='{')-(source[end]=='}');end+=1
   body=source[match.end():end]
   if re.search(r'syncShutdown|semaphore|DispatchGroup|\.wait\s*\(',body): errors.append(str(path))
if errors: print('\n'.join(errors),file=sys.stderr);sys.exit(1)
print('No synchronous shutdown wait in deinit.')
PY
