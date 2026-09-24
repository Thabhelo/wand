import schema from '../../contracts/v1.schema.json' with {type:'json'};
import base from '../../connector/openapi.json' with {type:'json'};
import catalog from '../../contracts/actions.json' with {type:'json'};
const SCOPES=catalog.map(a=>'wand:'+a.name);
export function publicSpec(env) {
 const spec=structuredClone(base);
 spec.info={...spec.info,title:'Wand device control API',version:'0.10.0',description:'Control only the Macs and actions approved by the user. Poll commands until succeeded or failed. Offline commands are never queued.'};
 spec.servers=[{url:'https://api.getwand.app/connector'}];
 spec['x-wand-auth-configured']=Boolean(env.FIREBASE_PROJECT_ID&&env.MUSE_CLIENT_IDS);
 spec.components.securitySchemes.userOAuth={type:'oauth2',flows:{authorizationCode:{authorizationUrl:'https://api.getwand.app/authorize',tokenUrl:'https://api.getwand.app/oauth/token',scopes:Object.fromEntries(SCOPES.map(s=>[s,s.slice(5).replaceAll('_',' ')]))}},description:'Registered clients only. PKCE S256 and resource=https://api.getwand.app/connector required. Firebase sign-in and explicit device/action consent take place on Wand.'};
 for(const path of Object.keys(spec.paths))if(!['/v1/devices','/v1/commands','/v1/commands/{cid}'].includes(path))delete spec.paths[path];
 for(const path of Object.values(spec.paths))for(const operation of Object.values(path)){
  operation.security=[{userOAuth:[]}];
  operation.responses['403']={description:'The device or action is outside the user’s approved permissions'};
  operation.responses['503']={description:'Service temporarily unavailable'};
 }
 const convert=value=>JSON.parse(JSON.stringify(value).replaceAll('#/$defs/','#/components/schemas/'));
 for(const name of ['DeviceCapabilities','CapabilityPermissions','ActionCapability'])spec.components.schemas[name]=convert(schema.$defs[name]);
 spec.paths['/v1/devices/{device_id}/capabilities']={get:{operationId:'getDeviceCapabilities',summary:'Check this Mac’s implemented actions, features and current permission report',description:'Check before offering actions. Unknown means this agent does not report capabilities; never infer support from its version. Supported does not mean authorized or ready. Permission reports become unknown when stale; execution always rechecks. Metadata does not grant access.',security:[{userOAuth:[]}],parameters:[{name:'device_id',in:'path',required:true,schema:{type:'string',format:'uuid'}}],responses:{'200':{description:'Device capability report',content:{'application/json':{schema:{$ref:'#/components/schemas/DeviceCapabilities'}}}},'401':{description:'Authentication required'},'404':{description:'Device not found or outside consent'},'429':{description:'Too many capability requests'}}}};
 return spec;
}
