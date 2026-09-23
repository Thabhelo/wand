import {DurableObject} from 'cloudflare:workers';

export const CLEANUP_INTERVAL = 60 * 60 * 1000;
const BATCH_SIZE = 500;

// One account-wide scheduler. No device contents or credentials are stored here.
export class Cleanup extends DurableObject {
 async ensure() {
  if(await this.ctx.storage.getAlarm() === null) await this.ctx.storage.setAlarm(Date.now()+1000);
  const state=await this.ctx.storage.get('status')||{};
  return {last_success:state.last_success||null,failures:state.failures||0,next_run:await this.ctx.storage.getAlarm()};
 }
 async alarm() {
  const now=Date.now();
  // Keep a future wake-up even if execution is interrupted or automatic retries run out.
  await this.ctx.storage.setAlarm(now+CLEANUP_INTERVAL);
  const previous=await this.ctx.storage.get('status')||{};
  try {
   const db=this.env.DB;
   const expiredPairing='SELECT code FROM pairing WHERE deadline<? ORDER BY deadline,code LIMIT '+BATCH_SIZE;
   const results=await db.batch([
    db.prepare('DELETE FROM consent_requests WHERE id IN (SELECT id FROM consent_requests WHERE expires_at<? ORDER BY expires_at,id LIMIT '+BATCH_SIZE+')').bind(now),
    db.prepare('DELETE FROM devices WHERE user_id IS NULL AND id IN (SELECT device_id FROM pairing WHERE code IN ('+expiredPairing+'))').bind(now),
    db.prepare('DELETE FROM pairing WHERE code IN ('+expiredPairing+')').bind(now)
   ]);
   await this.ctx.storage.put('status',{last_success:now,failures:0});
   // Drain a backlog in bounded batches, then return to hourly maintenance.
   if(results.some(r=>r.meta.changes>=BATCH_SIZE))await this.ctx.storage.setAlarm(now+60000);
  } catch {
   const failures=Math.min(20,(previous.failures||0)+1);
   await this.ctx.storage.put('status',{last_success:previous.last_success||null,failures});
   await this.ctx.storage.setAlarm(Date.now()+Math.min(CLEANUP_INTERVAL,300000*2**(failures-1)));
   // Errors contain no database rows, user IDs, or credentials.
   console.error(JSON.stringify({event:'cleanup_failed',failures}));
  }
 }
}
