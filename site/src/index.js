import {support} from './support.js';
const missing = () => Response.json({error:{code:'service_not_configured',message:'Wand online connections are not available yet.'}},{status:503,headers:{'Cache-Control':'no-store'}});
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname === 'www.getwand.app') { url.hostname='getwand.app'; return Response.redirect(url,308); }
    if (url.pathname === '/connect') { return Response.redirect('https://app.getwand.app/',302); }
    if (url.pathname === '/api/support') return support(request,env);
    const dashboard = url.hostname === 'app.getwand.app';
    // Browser simulator transports a public device ID only; relay hello still authenticates the token.
    if (dashboard && url.pathname === '/review-device') {
      const did=url.searchParams.get('device_id');
      if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket' || !/^[0-9a-f-]{36}$/i.test(did||'')) return new Response('Invalid device socket',{status:400});
      if (request.headers.get('Origin') !== 'https://app.getwand.app') return new Response('Invalid origin',{status:403});
      if (env.RELAY_ORIGIN !== 'https://api.getwand.app') return missing();
      const headers=new Headers(request.headers); headers.set('X-Wand-Device-ID',did);
      return fetch(new Request('https://api.getwand.app/v1/ws/device',{headers}));
    }
    if (dashboard && (url.pathname === '/config' || url.pathname.startsWith('/v1/'))) {
      if (!env.RELAY_ORIGIN) return missing();
      const upstream = new URL(env.RELAY_ORIGIN);
      if (upstream.protocol !== 'https:' || upstream.hostname !== 'api.getwand.app') return missing();
      upstream.pathname=url.pathname; upstream.search=url.search;
      // No request/body logging; OAuth bearer remains confined to the configured relay.
      try { return await fetch(new Request(upstream,request),{redirect:'manual'}); }
      catch { return missing(); }
    }
    if (!['GET','HEAD'].includes(request.method)) return new Response('Method not allowed',{status:405});
    if (dashboard && url.pathname === '/') url.pathname='/dashboard';
    const response=await env.ASSETS.fetch(new Request(url,request));
    const headers=new Headers(response.headers);
    headers.set('X-Content-Type-Options','nosniff');
    headers.set('Referrer-Policy','no-referrer');
    headers.set('X-Frame-Options','DENY');
    headers.set('Permissions-Policy','camera=(), microphone=(), geolocation=()');
    if(dashboard) headers.set('Cache-Control','no-store');
    // Account and reviewer screens are usable links, not public search results.
    if (dashboard || /^\/(dashboard|review|consent)(\/|$)/.test(url.pathname)) {
      headers.set('X-Robots-Tag','noindex');
    }
    return new Response(response.body,{status:response.status,headers});
  }
};
