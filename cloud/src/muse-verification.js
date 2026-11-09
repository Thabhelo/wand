// Public proof of host control, never an authentication credential.
// Only the configured, unexpired challenge is served, without redirects or HTML.
export function museVerification(request, env, now = Date.now()) {
 const url = new URL(request.url);
 if (!url.pathname.startsWith('/.well-known/muse-challenge/')) return null;
 const challenge = env.MUSE_VERIFICATION_CHALLENGE;
 const expiry = Date.parse(env.MUSE_VERIFICATION_EXPIRES || '');
 if (request.method !== 'GET' || !/^[a-f0-9]{64}$/.test(challenge || '') ||
     !Number.isFinite(expiry) || expiry <= now ||
     url.pathname !== '/.well-known/muse-challenge/' + challenge) {
  return new Response('Not found', {status: 404, headers: {'Cache-Control': 'no-store'}});
 }
 return new Response('muse-challenge=' + challenge, {headers: {
  'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff'
 }});
}
