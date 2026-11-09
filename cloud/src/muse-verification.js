// Public proof of host control, never an authentication credential.
// Only the configured, unexpired challenge is served, without redirects or HTML.
export function museVerification(request, env, now = Date.now()) {
 const url = new URL(request.url);
 if (!url.pathname.startsWith('/.well-known/muse-challenge/')) return null;
 const challenge = env.MUSE_VERIFICATION_CHALLENGE;
 const expiry = Date.parse(env.MUSE_VERIFICATION_EXPIRES || '');
 if (!['GET','HEAD','OPTIONS'].includes(request.method) || !/^[a-f0-9]{64}$/.test(challenge || '') ||
     !Number.isFinite(expiry) || expiry <= now ||
     url.pathname !== '/.well-known/muse-challenge/' + challenge) {
  return new Response('Not found', {status: 404, headers: {'Cache-Control': 'no-store'}});
 }
 if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers: {
  'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
  'Cache-Control': 'no-store'
 }});
 return new Response(request.method === 'HEAD' ? null : 'muse-challenge=' + challenge, {headers: {
  'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*', 'Content-Length': String(('muse-challenge=' + challenge).length),
  'X-Content-Type-Options': 'nosniff'
 }});
}
