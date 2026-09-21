import {writeFile} from 'node:fs/promises';
import {publicSpec} from '../cloud/src/openapi.js';
import schema from '../contracts/v1.schema.json' with {type:'json'};
import actions from '../contracts/actions.json' with {type:'json'};
const spec=publicSpec({});
const remap=v=>JSON.parse(JSON.stringify(v).replaceAll('#/$defs/','#/components/schemas/'));
Object.assign(spec.components.schemas,remap(schema.$defs));
await writeFile(new URL('../connector/openapi.json',import.meta.url),JSON.stringify(spec,null,2)+'\n');
await writeFile(new URL('../connector/manifest.json',import.meta.url),JSON.stringify({name:'Wand',version:'0.10.0',format_status:'Wand internal manifest; Meta import format and client registration not yet verified',openapi:'openapi.json',operator_instructions:'OPERATOR.md',actions},null,2)+'\n');
