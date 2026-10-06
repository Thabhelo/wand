// Registers one public (PKCE-only) OAuth client in the relay's production KV store.
// Wand has no dynamic client registration: this script is the only way a client is created.
// Usage: node scripts/register-client.mjs "<client name>" "<exact https callback>" [--apply]
// Without --apply it prints the record and changes nothing. After applying, add the printed
// client ID to MUSE_CLIENT_IDS in wrangler.jsonc and deploy; an unlisted client cannot reach consent.
import {execFileSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
const [name,callback,...flags]=process.argv.slice(2);
if(!name||!callback){console.error('Usage: node scripts/register-client.mjs "<client name>" "<exact https callback>" [--apply]');process.exit(2)}
const url=new URL(callback);
if(url.protocol!=='https:'||url.username||url.password||url.hash||url.href!==callback){console.error('The callback must be one exact https URL with no credentials or fragment.');process.exit(2)}
const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
const clientId=Array.from(randomBytes(16),b=>alphabet[b%alphabet.length]).join('');
// Same shape @cloudflare/workers-oauth-provider stores for createClient() with tokenEndpointAuthMethod "none".
const record={clientId,redirectUris:[callback],clientName:name,grantTypes:['authorization_code','refresh_token'],responseTypes:['code'],registrationDate:Math.floor(Date.now()/1000),tokenEndpointAuthMethod:'none',authMethodExplicit:true};
console.log(JSON.stringify(record,null,1));
if(!flags.includes('--apply')){console.log('Dry run. Add --apply to write this client to production.');process.exit(0)}
execFileSync('npx',['wrangler','kv','key','put','--remote','--binding','OAUTH_KV','client:'+clientId,JSON.stringify(record)],{stdio:'inherit'});
console.log('Registered client '+clientId+'. Add it to MUSE_CLIENT_IDS and deploy.');
