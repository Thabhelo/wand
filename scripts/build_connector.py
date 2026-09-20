import json
from pathlib import Path
from relay.app import create_app
from relay.store import SQLiteRepository
from relay.openapi import public_spec
from contracts import ACTIONS
root=Path(__file__).resolve().parents[1]
app=create_app(SQLiteRepository(':memory:'))
(root/'connector/openapi.json').write_text(json.dumps(public_spec(app),indent=2)+'\n')
(root/'connector/manifest.json').write_text(json.dumps({'name':'MacBridge','version':'0.3.0','format_status':'MacBridge internal manifest; Meta import format not yet verified','openapi':'openapi.json','operator_instructions':'OPERATOR.md','actions':ACTIONS},indent=2)+'\n')

app.state.repository.close()
