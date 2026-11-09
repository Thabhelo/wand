// Exact temporary append applied to the existing e11c2728 dashboard bundle on November 9.
// The canonical build uses src/muse-verification.js with wrangler vars instead.

// Public proof of host control, never an authentication credential.
// Only the configured, unexpired challenge is served, without redirects or HTML.
function museVerification(request, env, now = Date.now()) {
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

const musePreviousFetch = entry_default.fetch;
entry_default.fetch = (request, env, ctx) => museVerification(request, {...env, MUSE_VERIFICATION_CHALLENGE: '418da93af2297ca7bf7b8dff7f618e63a20fb5d9e380b5be48c233b6bad5e926', MUSE_VERIFICATION_EXPIRES: '2026-11-10T07:57:00Z'}) || musePreviousFetch(request, env, ctx);
