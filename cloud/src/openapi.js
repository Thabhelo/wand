import base from '../../connector/openapi.json';

// The deployed API is the source of connection URLs; never publish placeholder OAuth URLs.
export function publicSpec(env) {
  const spec = structuredClone(base);
  spec.info = {...spec.info, title:'Wand device control API', version:'0.9.1', description:'Control a paired Mac through Wand. Commands are asynchronous: poll until succeeded or failed. Offline commands are rejected, never queued.'};
  spec.servers = [{url:'https://api.getwand.app'}];
  spec['x-wand-auth-configured'] = Boolean(env.AUTH0_ISSUER && env.AUTH0_WEB_CLIENT_ID && env.AUTH0_ALLOWED_CLIENT_IDS);
  if (spec['x-wand-auth-configured']) {
    const issuer = new URL(env.AUTH0_ISSUER);
    if (issuer.protocol !== 'https:' || issuer.username || issuer.password || issuer.search || issuer.hash) throw Error('Invalid auth issuer');
    spec.components.securitySchemes.userOAuth.flows.authorizationCode.authorizationUrl = new URL('authorize', issuer).href;
    spec.components.securitySchemes.userOAuth.flows.authorizationCode.tokenUrl = new URL('oauth/token', issuer).href;
  } else {
    spec.components.securitySchemes.userOAuth = {type:'http',scheme:'bearer',bearerFormat:'JWT',description:'Account sign-in is not configured yet. Protected operations reject requests until configuration is complete.'};
    for (const path of Object.values(spec.paths)) for (const operation of Object.values(path)) {
      if (operation.security?.some(item => item.userOAuth)) operation.security = [{userOAuth:[]}];
    }
  }
  for (const path of Object.values(spec.paths)) for (const operation of Object.values(path)) {
    operation.responses['503'] = {description:'Service unavailable or sign-in not configured',content:{'application/json':{schema:{$ref:'#/components/schemas/ErrorResponse'}}}};
  }
  return spec;
}
