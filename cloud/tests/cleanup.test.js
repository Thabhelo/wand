import {env} from 'cloudflare:workers';
import {runInDurableObject,runDurableObjectAlarm} from 'cloudflare:test';
import {beforeAll,beforeEach,expect,it} from 'vitest';
import migration from '../migrations/0001_registry.sql?raw';
import connections from '../migrations/0002_connections.sql?raw';
import worker from '../src/index.js';
import {CLEANUP_INTERVAL} from '../src/cleanup.js';
beforeAll(async()=>{for(const sql of (migration+connections).split(';').filter(s=>s.trim()))await env.DB.prepare(sql).run()});
beforeEach(async()=>{for(const table of ['pairing','devices','consent_requests'])await env.DB.prepare('DELETE FROM '+table).run()});
it('starts once and preserves an existing alarm',async()=>{const stub=env.CLEANUP.getByName(crypto.randomUUID());const a=await stub.ensure();const b=await stub.ensure();expect(a.next_run).toBe(b.next_run);expect(a.last_success).toBe(null)});
it('health check bootstraps the production singleton',async()=>{const r=await worker.fetch(new Request('https://api.example/healthz'),env);expect(r.status).toBe(200);expect((await r.json()).cleanup.next_run).toBeGreaterThan(Date.now())});
it('cleans expired rows, preserves claimed Macs and live requests, and reschedules',async()=>{
 const now=Date.now(),stub=env.CLEANUP.getByName(crypto.randomUUID());
 for(const [id,user,deadline]of [['abandoned',null,now-1],['claimed','alice',now-1],['pending',null,now+600000]]){
  await env.DB.prepare('INSERT INTO devices VALUES(?,?,?, ?,?,NULL,?,NULL)').bind(id,user,'mac','Fixture','test',new Date().toISOString()).run();
  await env.DB.prepare('INSERT INTO pairing VALUES(?,?,?,?,NULL,NULL)').bind(id,id,id,deadline).run();
 }
 for(const [id,expiry]of [['old',now-1],['new',now+600000]])await env.DB.prepare('INSERT INTO consent_requests VALUES(?,?,NULL,?,0)').bind(id,'{}',expiry).run();
 await stub.ensure();await runDurableObjectAlarm(stub);
 expect((await env.DB.prepare('SELECT id FROM devices ORDER BY id').all()).results.map(r=>r.id)).toEqual(['claimed','pending']);
 expect((await env.DB.prepare('SELECT code FROM pairing').all()).results.map(r=>r.code)).toEqual(['pending']);
 expect((await env.DB.prepare('SELECT id FROM consent_requests').all()).results.map(r=>r.id)).toEqual(['new']);
 const status=await stub.ensure();expect(status.last_success).toBeGreaterThanOrEqual(now);expect(status.failures).toBe(0);expect(status.next_run).toBeGreaterThan(now+CLEANUP_INTERVAL-1000);
 // Repeated delivery is safe.
 await runDurableObjectAlarm(stub);expect((await env.DB.prepare('SELECT COUNT(*) n FROM devices').first()).n).toBe(2);
});
it('retries a database failure and recovers without exposing its error',async()=>{
 const stub=env.CLEANUP.getByName(crypto.randomUUID());await stub.ensure();
 await runInDurableObject(stub,async instance=>{const original=instance.env.DB;instance.env.DB={prepare:()=>{throw Error('private database details')}};try{await instance.alarm()}finally{instance.env.DB=original}});
 const failed=await stub.ensure();expect(failed.failures).toBe(1);expect(failed.next_run-Date.now()).toBeGreaterThan(290000);expect(failed.next_run-Date.now()).toBeLessThanOrEqual(300000);
 await runDurableObjectAlarm(stub);expect((await stub.ensure()).failures).toBe(0);
});
it('drains large backlogs in bounded batches',async()=>{
 const stub=env.CLEANUP.getByName(crypto.randomUUID());
 await env.DB.prepare("WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<501) INSERT INTO consent_requests SELECT 'old-'||x,'{}',NULL,0,0 FROM n").run();
 await stub.ensure();await runDurableObjectAlarm(stub);
 expect((await env.DB.prepare('SELECT COUNT(*) n FROM consent_requests').first()).n).toBe(1);
 expect((await stub.ensure()).next_run-Date.now()).toBeLessThanOrEqual(60000);
 await runDurableObjectAlarm(stub);expect((await env.DB.prepare('SELECT COUNT(*) n FROM consent_requests').first()).n).toBe(0);
 expect((await stub.ensure()).next_run-Date.now()).toBeGreaterThan(CLEANUP_INTERVAL-1000);
});
it('caps retry delays and keeps retrying after prolonged failure',async()=>{
 const stub=env.CLEANUP.getByName(crypto.randomUUID());await stub.ensure();
 await runInDurableObject(stub,async instance=>{const original=instance.env.DB;instance.env.DB={prepare:()=>{throw Error('unavailable')}};try{for(let i=0;i<8;i++)await instance.alarm()}finally{instance.env.DB=original}});
 const status=await stub.ensure();expect(status.failures).toBe(8);expect(status.next_run-Date.now()).toBeGreaterThan(CLEANUP_INTERVAL-1000);expect(status.next_run-Date.now()).toBeLessThanOrEqual(CLEANUP_INTERVAL);
});
it('health reports a failed cleanup without leaking database details',async()=>{
 const stub=env.CLEANUP.getByName('registry');
 await runInDurableObject(stub,async instance=>{await instance.ctx.storage.put('status',{last_success:Date.now(),failures:1})});
 const r=await worker.fetch(new Request('https://api.example/healthz'),env);expect(r.status).toBe(503);const data=await r.json();expect(data.status).toBe('degraded');expect(data.cleanup.failures).toBe(1);
});
