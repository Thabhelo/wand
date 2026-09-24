import {env} from 'cloudflare:workers';
import {evictDurableObject,runInDurableObject} from 'cloudflare:test';
import {expect,it} from 'vitest';

const COMPLETED_COUNT=5000;
const pendingQuery=/^SELECT (?:created|\*) FROM commands WHERE status IN \('dispatched','delivered'\)$/;

function seedHistory(instance){
 instance.sql.exec(`WITH RECURSIVE sequence(n) AS (
  VALUES(1) UNION ALL SELECT n+1 FROM sequence WHERE n<?
 ) INSERT INTO commands
 SELECT 'completed-'||n,'owner','get_state','succeeded',NULL,'old',?,'client','test'
 FROM sequence`,COMPLETED_COUNT,Date.now()-3600000);
}

function seedPending(instance,id,status,generation,created=Date.now()){
 instance.sql.exec('INSERT INTO commands VALUES(?,?,?,?,?,?,?,?,?)',id,'owner','mute',status,null,generation,created,'client','test');
}

async function measurePendingQueries(instance,operation){
 const original=instance.sql,cursors=[];
 instance.sql={exec(query,...bindings){
  const cursor=original.exec(query,...bindings);
  if(pendingQuery.test(query))cursors.push(cursor);
  return cursor;
 }};
 try{
  await operation();
  return cursors.map(cursor=>cursor.rowsRead);
 }finally{instance.sql=original;}
}

it('schedules pending work without reading completed history',async()=>{
 const stub=env.DEVICES.getByName(crypto.randomUUID());
 const result=await runInDurableObject(stub,async instance=>{
  seedHistory(instance);
  seedPending(instance,'pending-a','dispatched','live');
  seedPending(instance,'pending-b','delivered','live');
  try{
   const indexed=await measurePendingQueries(instance,()=>instance.schedule());
   const deadline=await instance.ctx.storage.getAlarm();
   // Establish the previous cost using this disposable object's database only.
   instance.sql.exec('DROP INDEX commands_pending');
   const unindexed=await measurePendingQueries(instance,()=>instance.schedule());
   return {indexed,unindexed,deadline,now:Date.now()};
  }finally{await instance.ctx.storage.deleteAlarm();}
 });
 expect(result.indexed).toHaveLength(1);
 expect(result.indexed[0]).toBeLessThanOrEqual(8);
 expect(result.unindexed[0]).toBeGreaterThanOrEqual(COMPLETED_COUNT);
 expect(result.deadline).toBeGreaterThan(result.now);
 expect(result.deadline-result.now).toBeLessThanOrEqual(15001);
 console.info('Pending schedule rows read:',{indexed:result.indexed,unindexed:result.unindexed});
});

it('adds the pending index when an existing device wakes without losing history',async()=>{
 const stub=env.DEVICES.getByName(crypto.randomUUID());
 await runInDurableObject(stub,instance=>{
  seedHistory(instance);
  seedPending(instance,'existing-pending','dispatched','live');
  instance.sql.exec('DROP INDEX commands_pending');
 });
 await evictDurableObject(stub);
 const result=await runInDurableObject(stub,async instance=>{
  try{
   const indexes=instance.sql.exec("SELECT name FROM sqlite_master WHERE type='index' AND name='commands_pending'").toArray();
   const reads=await measurePendingQueries(instance,()=>instance.schedule());
   const completed=instance.sql.exec("SELECT COUNT(*) AS n FROM commands WHERE status='succeeded'").one().n;
   return {indexes,reads,completed};
  }finally{await instance.ctx.storage.deleteAlarm();}
 });
 expect(result.indexes).toEqual([{name:'commands_pending'}]);
 expect(result.completed).toBe(COMPLETED_COUNT);
 expect(result.reads).toHaveLength(1);
 expect(result.reads[0]).toBeLessThanOrEqual(4);
});

it('keeps timeout and generation fencing correct while scanning only pending commands',async()=>{
 const stub=env.DEVICES.getByName(crypto.randomUUID());
 const result=await runInDurableObject(stub,async instance=>{
  seedHistory(instance);
  instance.put('device_id','test-device');
  seedPending(instance,'expired','dispatched','old',Date.now()-16000);
  seedPending(instance,'live-a','dispatched','live');
  seedPending(instance,'live-b','delivered','live');
  seedPending(instance,'other-generation','delivered','other');
  try{
   const alarmReads=await measurePendingQueries(instance,()=>instance.alarm());
   const failureReads=await measurePendingQueries(instance,()=>instance.failPending('device_reconnected','live'));
   const rows=instance.sql.exec("SELECT id,status,error FROM commands WHERE id IN ('expired','live-a','live-b','other-generation') ORDER BY id").toArray();
   const audit=instance.sql.exec('SELECT command_id,result_summary FROM audit ORDER BY command_id').toArray();
   const completed=instance.sql.exec("SELECT COUNT(*) AS n FROM commands WHERE status='succeeded'").one().n;
   return {alarmReads,failureReads,rows,audit,completed};
  }finally{await instance.ctx.storage.deleteAlarm();}
 });
 expect(result.alarmReads).toHaveLength(2);
 expect(result.alarmReads.every(reads=>reads<=12)).toBe(true);
 expect(result.failureReads).toHaveLength(1);
 expect(result.failureReads[0]).toBeLessThanOrEqual(9);
 expect(result.rows).toEqual([
  {id:'expired',status:'failed',error:'command_timeout'},
  {id:'live-a',status:'failed',error:'device_reconnected'},
  {id:'live-b',status:'failed',error:'device_reconnected'},
  {id:'other-generation',status:'delivered',error:null},
 ]);
 expect(result.audit).toEqual([
  {command_id:'expired',result_summary:'command_timeout'},
  {command_id:'live-a',result_summary:'device_reconnected'},
  {command_id:'live-b',result_summary:'device_reconnected'},
 ]);
 expect(result.completed).toBe(COMPLETED_COUNT);
 console.info('Pending lifecycle rows read:',{alarm:result.alarmReads,failure:result.failureReads});
});
