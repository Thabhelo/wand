.PHONY: contracts fixtures test swift-check verify spike
contracts:
	python3 scripts/build_contracts.py
fixtures:
	.venv/bin/python -m harness.build_fixtures
test:
	.venv/bin/python -m unittest discover -s tests -v
swift-check:
	python3 scripts/build_swift_probe.py
verify: swift-check
	MACBRIDGE_SWIFT_PROBE="$(CURDIR)/.build/direct/ProtocolProbe" .venv/bin/python -m unittest discover -s tests -v
spike:
	python3 spikes/inspect_platform.py

.PHONY: sandbox relay connector
sandbox:
	.venv/bin/python -m harness.sandbox
relay:
	.venv/bin/uvicorn relay.app:create_app --factory --host 127.0.0.1 --port 8080 --no-access-log --ws-max-size 65536
connector:
	PYTHONPATH=. .venv/bin/python scripts/build_connector.py
