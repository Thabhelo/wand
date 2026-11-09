// Preserve the existing registered client and grants; add only Meta's portal callbacks.
// Run from cloud/: node scripts/update-muse-callbacks.mjs [--apply]
import {execFileSync} from 'node:child_process';
const key='client:kqQLjzgKBLLzJ7Ff';
const callbacks=['https://muse.ai/api/hatch/oauth/callback','https://platform.muse.ai/oauth/credential-test/callback'];
const current=JSON.parse(execFileSync('npx',['wrangler','kv','key','get','--remote','--binding','OAUTH_KV',key],{encoding:'utf8'}));
if(current.clientId!=='kqQLjzgKBLLzJ7Ff'||!Array.isArray(current.redirectUris)||current.tokenEndpointAuthMethod!=='none')throw Error('Unexpected client record; no changes written');
const updated={...current,redirectUris:[...new Set([...current.redirectUris,...callbacks])]};
if(process.argv.includes('--apply')){
 execFileSync('npx',['wrangler','kv','key','put','--remote','--binding','OAUTH_KV',key,JSON.stringify(updated)],{stdio:'inherit'});
 const check=JSON.parse(execFileSync('npx',['wrangler','kv','key','get','--remote','--binding','OAUTH_KV',key],{encoding:'utf8'}));
 if(!callbacks.every(url=>check.redirectUris.includes(url)))throw Error('Callback readback did not confirm update');
 console.log('Muse callback update confirmed. Existing callbacks retained.');
}else console.log('Dry run: would add '+callbacks.join(', ')+'. Existing callbacks retained. Use --apply to write.');
