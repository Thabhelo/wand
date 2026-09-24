import {expect,it} from 'vitest';
import {publicSpec} from '../src/openapi.js';
it('publishes only scoped connector operations',()=>{
 const spec=publicSpec({});expect(spec.servers[0].url).toBe('https://api.getwand.app/connector');
 expect(spec['x-wand-auth-configured']).toBe(false);
 expect(Object.keys(spec.paths).sort()).toEqual(['/v1/commands','/v1/commands/{cid}','/v1/devices','/v1/devices/{device_id}/capabilities']);
 expect(spec.paths['/v1/commands'].post.responses['202']).toBeDefined();
 expect(JSON.stringify(spec)).not.toContain('YOUR_AUTH0_DOMAIN');
});
it('uses Wand OAuth, never Firebase ID tokens as connector authority',()=>{
 const spec=publicSpec({FIREBASE_PROJECT_ID:'wand-test',MUSE_CLIENT_IDS:'muse'});
 expect(spec['x-wand-auth-configured']).toBe(true);
 expect(spec.components.securitySchemes.userOAuth.flows.authorizationCode.tokenUrl).toBe('https://api.getwand.app/oauth/token');
 expect(spec.components.securitySchemes.userOAuth.flows.authorizationCode.scopes['wand:lock_screen']).toBeDefined();
});
