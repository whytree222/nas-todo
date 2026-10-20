"""Isolated integration-test bridge, not a production service endpoint."""
import json
from pathlib import Path
import sys
sys.stdin.reconfigure(encoding='utf-8')

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import ApiError, Config, SyncService

service = SyncService(Config(Path(sys.argv[1]), 'integration-only-personal-token-' + 'x' * 32))
for line in sys.stdin:
    try:
        request = json.loads(line)
        method = service.sync_personal if request['endpoint'] == 'personal' else service.sync
        result = {'data': method(request['payload'])}
    except ApiError as error:
        result = {'error': {'code': error.code, 'message': error.message}}
    print(json.dumps(result, ensure_ascii=True), flush=True)
