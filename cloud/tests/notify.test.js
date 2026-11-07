import {expect,it} from 'vitest';
import {DEFAULT_MAIL_FROM,formatUtc,offlineEmail,relative,sendOfflineEmail} from '../src/notify.js';
const seen=Date.UTC(2026,10,7,0,54);
const notice={to:'owner@example.com',deviceName:'Office Mac',lastSeen:new Date(seen).toISOString()};
it('formats times in UTC with a relative phrase',()=>{
 expect(formatUtc(seen)).toBe('7 November 2026 at 00:54 UTC');
 expect(relative(seen,seen+30000)).toBe('a moment ago');
 expect(relative(seen,seen+30*60000)).toBe('30 minutes ago');
 expect(relative(seen,seen+65*60000)).toBe('about an hour ago');
 expect(relative(seen,seen+6*3600000+90000)).toBe('about 6 hours ago');
 expect(relative(seen,seen+3*86400000)).toBe('about 3 days ago');
});
it('writes the subject, body and footer in the dashboard voice',()=>{
 const m=offlineEmail({...notice,now:seen+6*3600000});
 expect(m.subject).toBe('Wand on Office Mac has been offline since 7 November 2026 at 00:54 UTC');
 expect(m.text).toContain('last seen on 7 November 2026 at 00:54 UTC, about 6 hours ago');
 expect(m.text).toContain('Commands from your phone or from Muse will fail until Wand is opened on that Mac');
 expect(m.text).toContain('once per outage');
 expect(m.text).toContain('You receive this because owner@example.com owns this Mac in Wand. Disconnect the Mac at https://app.getwand.app to stop these.');
 expect(m.html).toContain('<a href="https://app.getwand.app"');
 expect(m.html).toContain('owner@example.com owns this Mac');
 for(const part of [m.subject,m.text,m.html.replace('<!doctype html>','')])expect(part).not.toContain('!');
 // Device names are owner-controlled text and must not become markup.
 const hostile=offlineEmail({...notice,deviceName:'<script>alert(1)</script>'});
 expect(hostile.html).not.toContain('<script>');expect(hostile.html).toContain('&lt;script&gt;');
 expect(offlineEmail({...notice,lastSeen:seen}).subject).toBe(m.subject);
});
it('sends through the EMAIL binding from the configured sender',async()=>{
 const calls=[];const env={EMAIL:{send:async m=>{calls.push(m);return {messageId:'abc'}}}};
 expect(await sendOfflineEmail(env,notice)).toEqual({sent:true,messageId:'abc'});
 expect(calls).toHaveLength(1);
 expect(calls[0].to).toBe('owner@example.com');
 expect(calls[0].from).toEqual({email:DEFAULT_MAIL_FROM,name:'Wand'});
 expect(calls[0].subject).toMatch(/^Wand on Office Mac has been offline since /);
 expect(calls[0].text).toContain('once per outage');expect(calls[0].html).toContain('<p>');
 await sendOfflineEmail({...env,MAIL_FROM:'hello@example.org'},notice);
 expect(calls[1].from).toEqual({email:'hello@example.org',name:'Wand'});
});
it('skips quietly when the binding or sender is missing and surfaces provider errors',async()=>{
 expect(await sendOfflineEmail({},notice)).toEqual({sent:false,reason:'email_not_configured'});
 expect(await sendOfflineEmail({EMAIL:{}},notice)).toEqual({sent:false,reason:'email_not_configured'});
 expect(await sendOfflineEmail({EMAIL:{send:async()=>({})},MAIL_FROM:''},notice)).toEqual({sent:false,reason:'email_not_configured'});
 expect(await sendOfflineEmail({EMAIL:{send:async()=>({})}},{...notice,to:''})).toEqual({sent:false,reason:'email_not_configured'});
 await expect(sendOfflineEmail({EMAIL:{send:async()=>{throw Error('provider down')}}},notice)).rejects.toThrow('provider down');
});
