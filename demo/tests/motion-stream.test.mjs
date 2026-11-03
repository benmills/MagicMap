import test from 'node:test';
import assert from 'node:assert/strict';
import { inertiaStep, releaseVelocity, twoFingerMode, pair } from '../map-motion.mjs';
import { TileStream } from '../tile-stream.mjs';
const tick=()=>new Promise(resolve=>setTimeout(resolve,0));

test('momentum distance is independent of refresh rate and stops after a held release',()=>{
  const run=dt=>{let v=1,x=0;for(let t=0;t<960;t+=dt){const s=inertiaStep(v,0,dt);x+=s.dx;v=s.vx;}return x;};
  assert(Math.abs(run(16)-run(8))<1e-8);
  assert(run(16)>230 && run(16)<240);
  const samples=[{x:0,y:0,t:10},{x:30,y:10,t:50},{x:60,y:20,t:90}];
  assert.deepEqual(releaseVelocity(samples,200),[0,0]);
  assert.deepEqual(releaseVelocity(samples,95),[.75,.25]);
});
test('two fingers distinguish parallel pitch from a pinch or rotation',()=>{
  const start=pair([{x:0,y:0},{x:100,y:0}]);
  assert.equal(twoFingerMode(start,pair([{x:0,y:20},{x:100,y:20}])),'tilt');
  assert.equal(twoFingerMode(start,pair([{x:-20,y:20},{x:120,y:20}])),'transform');
  assert.equal(twoFingerMode(start,pair([{x:0,y:-10},{x:100,y:10}])),'transform');
  assert.equal(twoFingerMode(start,pair([{x:0,y:2},{x:100,y:2}])),null);
});
test('obsolete responses never commit and current visible work preempts prefetch',async()=>{
  const calls=[],applied=[],disposed=[];
  const job=(key,priority)=>({key,priority,run:signal=>new Promise(resolve=>calls.push({key,signal,resolve})),apply:v=>applied.push(v),discard:v=>disposed.push(v)});
  const stream=new TileStream(()=>{},1);
  stream.update([job('prefetch',50)]);await tick();
  stream.update([job('visible',0),job('prefetch',50)]);await tick();
  assert(calls[0].signal.aborted);
  assert.equal(calls[1].key,'visible');
  calls[0].resolve('stale');calls[1].resolve('current');await tick();
  assert.deepEqual(applied,[]); // Never allocate GPU resources in a fetch callback.
  assert.deepEqual(disposed,['stale']);
  stream.commit(1);
  assert.deepEqual(applied,['current']);
  stream.clear();
  for(const call of calls.slice(2)) call.resolve('cleanup');
  await tick();
});
test('a map switch discards queued results and cancellation is not an asset failure',async()=>{
  let complete;const applied=[];
  const stream=new TileStream(()=>{},2);
  stream.update([{key:'old',priority:0,run:()=>new Promise(resolve=>complete=resolve),apply:v=>applied.push(v)}]);
  await tick();stream.clear();complete('late');await tick();stream.commit();
  assert.deepEqual(applied,[]);assert.equal(stream.failed.size,0);
  stream.update([{key:'new',priority:0,run:()=>Promise.resolve('new'),apply:v=>applied.push(v)}]);
  await tick();stream.commit();assert.deepEqual(applied,['new']);
});
