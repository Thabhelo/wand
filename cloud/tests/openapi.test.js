import {expect,it} from 'vitest';
import {publicSpec} from '../src/openapi.js';
it('publishes usable paths without imaginary OAuth endpoints when auth is absent',()=>{
 const spec=publicSpec({});expect(spec.servers[0].url).toBe('https://api.getwand.app');
 expect(spec['x-wand-auth-configured']).toBe(false);
 expect(JSON.stringify(spec)).not.toContain('YOUR_AUTH0_DOMAIN');
 expect(spec.paths['/v1/commands'].post.responses['202']).toBeDefined();
 expect(spec.paths['/v1/commands'].post.security).toEqual([{userOAuth:[]}]);
});
it('builds OAuth metadata from the configured issuer without mutating the base',()=>{
 const spec=publicSpec({AUTH0_ISSUER:'https://tenant.auth0.com/',AUTH0_WEB_CLIENT_ID:'web',AUTH0_ALLOWED_CLIENT_IDS:'web'});
 expect(spec.components.securitySchemes.userOAuth.flows.authorizationCode.tokenUrl).toBe('https://tenant.auth0.com/oauth/token');
 expect(spec.paths['/v1/commands'].post.security).toEqual([{userOAuth:['macbridge:control']}]);
 expect(publicSpec({}).components.securitySchemes.userOAuth.type).toBe('http');
});
