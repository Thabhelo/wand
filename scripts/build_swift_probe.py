"""Direct Swift build fallback for a broken local SwiftPM ManifestAPI installation."""
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'.build/direct'
BUILD.mkdir(parents=True,exist_ok=True)
common=['swiftc','-swift-version','6','-module-cache-path','/private/tmp/macbridge-direct-module-cache']
def run(args): subprocess.run(args,check=True,cwd=ROOT)
core=ROOT/'agent/Sources/MacBridgeCore'
run(common+['-parse-as-library','-emit-library','-emit-module','-enable-testing','-module-name','MacBridgeCore','-emit-module-path',str(BUILD/'MacBridgeCore.swiftmodule'),*map(str,sorted(core.glob('*.swift'))),'-Xlinker','-install_name','-Xlinker','@rpath/libMacBridgeCore.dylib','-o',str(BUILD/'libMacBridgeCore.dylib')])
link=['-I',str(BUILD),'-L',str(BUILD),'-lMacBridgeCore','-Xlinker','-rpath','-Xlinker','@executable_path']
run(common+['-parse-as-library',*link,str(ROOT/'agent/Sources/ProtocolProbe/main.swift'),'-o',str(BUILD/'ProtocolProbe')])
# Standalone throwing assertions do not require XCTest (absent in this CLT install).
run(common+['-parse-as-library',*link,str(ROOT/'agent/Sources/PolicyChecks/main.swift'),'-o',str(BUILD/'PolicyChecks')])
run([str(BUILD/'PolicyChecks')])
run([str(BUILD/'ProtocolProbe'),'--schema',str(ROOT/'contracts/v1.schema.json'),'--validate-fixtures',str(ROOT/'contracts/fixtures.json')])
