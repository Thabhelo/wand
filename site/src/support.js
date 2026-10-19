import {supportEmail} from './email-template.js';
const reply = (status, message) => Response.json({message}, {status, headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...(status===429?{'Retry-After':'60'}:{})}});
const topics = new Set(['Connection','Mac controls','Account','Privacy','Something else']);
export async function support(request, env) {
  if (request.method !== 'POST') return reply(405,'Use the support form to send a message.');
  if (!['https://getwand.app','https://app.getwand.app'].includes(request.headers.get('Origin'))) return reply(403,'Please send your message from the Wand support page.');
  if (!request.headers.get('Content-Type')?.startsWith('application/json')) return reply(415,'Please reload the support page and try again.');
  try {
    if (!(await env.SUPPORT_LIMIT.limit({key:request.headers.get('CF-Connecting-IP') || 'unknown'})).success) return reply(429,'Please wait a minute before sending another message.');
    // Bound the stream, including requests without Content-Length.
    const reader=request.body?.getReader(); if (!reader) return reply(400,'Please add your message.');
    let size=0, chunks=[];
    while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>16384){await reader.cancel();return reply(413,'Your message is too long. Please keep it under 5,000 characters.');}chunks.push(value);}
    const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
    let data;try{data=JSON.parse(new TextDecoder().decode(bytes));}catch{return reply(400,'Please reload the page and try again.');}
    if(!data || typeof data!=='object') return reply(400,'Please complete the form.');
    const {email,message,topic,name='',website=''}=data;
    if(typeof email!=='string'||email.length>254||! /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email)||/[\r\n\x00-\x1f]/.test(email)) return reply(400,'Enter a valid email so we can reply.');
    if(typeof name!=='string'||name.length>100||/[\r\n\x00-\x1f]/.test(name)||website||!topics.has(topic)) return reply(400,'Please check the form and try again.');
    if(typeof message!=='string'||message.trim().length<10||message.length>5000) return reply(400,'Write a message between 10 and 5,000 characters.');
    if (!env.TURNSTILE_SECRET_KEY) return reply(503, 'The security check is temporarily unavailable. Please try again shortly.');
    const token = data['cf-turnstile-response'];
    if (typeof token !== 'string' || !token || token.length > 2048) return reply(400, 'Please complete the security check and try again.');
    const verification = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({secret: env.TURNSTILE_SECRET_KEY, response: token, remoteip: request.headers.get('CF-Connecting-IP') || undefined}),
      signal: AbortSignal.timeout(8000),
    });
    if (!verification.ok) return reply(503, 'The security check is temporarily unavailable. Please try again shortly.');
    const result = await verification.json();
    if (result.success !== true || result.action !== 'support' || !['getwand.app', 'app.getwand.app'].includes(result.hostname)) return reply(400, 'The security check expired or failed. Please try again.');
    if(!env.SUPPORT_RECIPIENT||!env.SUPPORT_EMAIL) return reply(503,'Support is temporarily unavailable. Please try again shortly.');
    await env.SUPPORT_EMAIL.send({from:{email:'support@getwand.app',name:'Wand Support'},to:env.SUPPORT_RECIPIENT,replyTo:email,subject:`Wand support: ${topic}`,...supportEmail({name,email,topic,message})});
    return reply(200,'Message sent. We’ll reply to your email.');
  } catch {
    // Never log message contents, visitor addresses, or provider errors.
    return reply(503,'We couldn’t send your message. Please try again shortly.');
  }
}
