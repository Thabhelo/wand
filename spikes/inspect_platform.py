"""Read-only discovery; presence of a path or property is NOT an action test."""
import json
from pathlib import Path
import platform
import xml.etree.ElementTree as ET
result={'macos':platform.mac_ver()[0], 'lock_executable_present':Path('/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession').is_file()}
for app in ['Safari','Google Chrome']:
    root=Path('/Applications')/(app+'.app')/'Contents/Resources'
    dictionaries=list(root.glob('*.sdef'))
    props=[]
    for dictionary in dictionaries:
        try:
            tree=ET.parse(dictionary)
            props.extend(p.attrib.get('name') for c in tree.iter('class') if c.attrib.get('name')=='tab' for p in c.findall('property'))
        except ET.ParseError: pass
    result[app]={'dictionaries_found':len(dictionaries),'tab_pinned_property_declared':'pinned' in props}
result['executed_actions']=[]
result['sleep_wake_verified']=False
result['caution']='Read-only discovery only; no OS behavior verified.'
print(json.dumps(result,indent=2))
