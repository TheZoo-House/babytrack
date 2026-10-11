import test from 'node:test';
import assert from 'node:assert/strict';
import { Store,hash } from './store.mjs';
import { createServer } from './main.mjs';
import { verifyApple } from './auth.mjs';
import { generateKeyPairSync,sign } from 'node:crypto';
async function fixture(t,options={}){const store=new Store();const server=createServer(store,options);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>{server.close();store.close();});const url='http://127.0.0.1:'+server.address().port;const call=async(path,body,token)=>{const res=await fetch(url+path,{method:body?'POST':'GET',headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined});return {status:res.status,body:await res.json()};};return {store,call};}
test('private routes require a session and preview is explicit',async t=>{const {call}=await fixture(t);assert.equal((await call('/v1/snapshot')).status,401);assert.equal((await call('/v1/auth/preview',{})).status,404);assert.equal((await call('/health')).status,200);});
test('POST routes reject JSON arrays and primitives at the shared boundary',async t=>{const {call}=await fixture(t,{preview:true});for(const body of [[],123,'invalid'])assert.equal((await call('/v1/auth/preview',body)).status,400);});
test('Apple challenge cannot be replayed',async t=>{const {call}=await fixture(t,{verify:async()=> 'synthetic-apple-user'});const {nonce}=(await call('/v1/auth/challenge',{})).body;const login=await call('/v1/auth/apple',{nonce,identityToken:'synthetic-test',name:'Sample User'});assert.equal(login.status,200);assert.equal((await call('/v1/snapshot',null,login.body.token)).status,200);assert.equal((await call('/v1/auth/apple',{nonce,identityToken:'synthetic-test'})).status,401);});
test('sync result returns rejected data without discarding other valid writes',async t=>{const {call}=await fixture(t,{preview:true});const login=(await call('/v1/auth/preview',{})).body;const results=await call('/v1/sync',{commands:[{id:'synthetic-op',action:'upsert',baseVersion:0,entity:{id:'synthetic-feed',type:'feeding',title:'Bottle',childID:'sample-child',at:1700000000,fields:{amount:'3',unit:'oz'}}},{id:'synthetic-bad',action:'upsert',entity:{}}]},login.token);assert.equal(results.status,200);assert.deepEqual(results.body.results.map(r=>r.status),['accepted','rejected']);assert.ok(results.body.snapshot.entities.some(e=>e.id==='synthetic-feed'));});
test('Apple identity verification checks signed audience, expiration and nonce',async()=>{const {publicKey,privateKey}=generateKeyPairSync('rsa',{modulusLength:2048});const jwk=publicKey.export({format:'jwk'});jwk.kid='synthetic-key';const header=Buffer.from(JSON.stringify({alg:'RS256',kid:jwk.kid})).toString('base64url');const nonce='synthetic-nonce';const claims={iss:'https://appleid.apple.com',sub:'synthetic-sub',aud:'house.thezoo.babytrack',exp:Date.now()/1000+300,iat:Date.now()/1000,nonce:hash(nonce)};const token=payload=>{const message=header+'.'+Buffer.from(JSON.stringify(payload)).toString('base64url');return message+'.'+sign('RSA-SHA256',Buffer.from(message),privateKey).toString('base64url');};const fetcher=async()=>({ok:true,json:async()=>({keys:[jwk]})});assert.equal(await verifyApple(token(claims),nonce,claims.aud,fetcher),'synthetic-sub');await assert.rejects(verifyApple(token({...claims,aud:'other'}),nonce,claims.aud,fetcher));await assert.rejects(verifyApple(token({...claims,exp:1}),nonce,claims.aud,fetcher));await assert.rejects(verifyApple(token({...claims,nonce:'wrong'}),nonce,claims.aud,fetcher));});

import {readFileSync} from 'node:fs';
test('Nara preview and commit are authorized and preview does not write',async t=>{
 const {call}=await fixture(t,{preview:true});const csv=readFileSync(new URL('../contracts/nara-sample.csv',import.meta.url),'utf8');
 assert.equal((await call('/v1/import/nara/preview',{csv,familyID:'foreign'})).status,401);
 const login=(await call('/v1/auth/preview',{})).body;const body={csv,familyID:login.snapshot.familyID};
 const before=login.snapshot.entities.length;const preview=await call('/v1/import/nara/preview',body,login.token);assert.equal(preview.status,200);assert.equal(preview.body.sourceRows,9);assert.equal((await call('/v1/snapshot',null,login.token)).body.entities.length,before);
 assert.equal((await call('/v1/import/nara/commit',{...body,familyID:'foreign'},login.token)).status,409);
 const committed=await call('/v1/import/nara/commit',body,login.token);assert.equal(committed.status,200);assert.equal(committed.body.snapshot.entities.length,before+11);
 const again=await call('/v1/import/nara/commit',body,login.token);assert.equal(again.body.duplicates,11);
});
test('caregiver profile endpoint authenticates and publishes only self changes to the family',async t=>{
 const {store,call}=await fixture(t);const a=store.login('photo-api-a','A');const b=store.login('photo-api-b','B');
 const ua=store.authenticate(a.token);store.join(store.authenticate(b.token),store.invite(ua).code);
 const photo='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5FoAAAAASUVORK5CYII=';
 assert.equal((await call('/v1/caregiver/profile',{photo})).status,401);
 assert.equal((await call('/v1/caregiver/profile',{photo,userID:'photo-api-b'},a.token)).status,400);
 assert.equal((await call('/v1/caregiver/profile',{photo},a.token)).status,200);
 assert.equal((await call('/v1/snapshot',null,b.token)).body.members.find(m=>m.id===ua.id).photo,photo);
 assert.equal((await call('/v1/caregiver/profile',{photo:null},a.token)).status,200);
 assert.equal((await call('/v1/snapshot',null,b.token)).body.members.find(m=>m.id===ua.id).photo,null);
});

test('authenticated users do not share a proxy rate limit and previews are separately bounded',async t=>{
 const {store,call}=await fixture(t,{preview:true,rateLimit:3,previewLimit:1});
 const a=store.login('limited-a'),b=store.login('limited-b');
 for(let i=0;i<3;i++)assert.equal((await call('/v1/snapshot',null,a.token)).status,200);
 assert.equal((await call('/v1/snapshot',null,a.token)).status,429);
 assert.equal((await call('/v1/snapshot',null,b.token)).status,200);
 assert.equal((await call('/v1/auth/preview',{})).status,200);
 assert.equal((await call('/v1/auth/preview',{})).status,429);
});

test('device registration, logout and account deletion are authorized and scoped',async t=>{
 const {store,call}=await fixture(t);const a=store.login('route-owner'),b=store.login('route-other');const token='ab'.repeat(32);
 assert.equal((await call('/v1/devices',{id:'phone',enabled:true,pushToken:token})).status,401);
 assert.equal((await call('/v1/devices',{id:'phone',enabled:true,pushToken:'invalid'},a.token)).status,400);
 assert.equal((await call('/v1/devices',{id:'phone',enabled:true,pushToken:token},a.token)).status,200);
 assert.equal(store.deliveryRecipients(store.authenticate(a.token).family).length,1);
 assert.equal((await call('/v1/auth/logout',{},a.token)).status,200);assert.equal((await call('/v1/snapshot',null,a.token)).status,401);
 const again=store.login('route-owner');assert.equal((await call('/v1/account/delete',{},again.token)).status,200);
 assert.equal((await call('/v1/snapshot',null,again.token)).status,401);assert.equal((await call('/v1/snapshot',null,b.token)).status,200);
});

test('original import source is fetched on demand only by its family and kept in export',async t=>{
 const {store,call}=await fixture(t,{preview:true});const csv=readFileSync(new URL('../contracts/nara-sample.csv',import.meta.url),'utf8');const a=store.preview(),u=store.authenticate(a.token);
 const imported=store.importNara(u,{csv,familyID:u.family,commit:true});const record=imported.snapshot.entities.find(e=>e.imported);
 assert.deepEqual(record.imported.raw,{});
 const source=await call('/v1/import-source/'+record.id,null,a.token);assert.equal(source.status,200);assert.ok(Object.keys(source.body.raw).length>0);
 const b=store.login('outside-import-family');assert.equal((await call('/v1/import-source/'+record.id,null,b.token)).status,404);
 const exported=await call('/v1/export',null,a.token);assert.ok(Object.keys(exported.body.entities.find(e=>e.id===record.id).imported.raw).length>0);
 assert.equal((await call('/v1/sync',{familyID:'another-family',commands:[]},a.token)).status,409);
});

test('Apple key rotation refreshes an otherwise valid warm cache',async()=>{
 const first=generateKeyPairSync('rsa',{modulusLength:2048}),second=generateKeyPairSync('rsa',{modulusLength:2048});
 const key=(pair,kid)=>({...pair.publicKey.export({format:'jwk'}),kid});const keys=[key(first,'rotation-one'),key(second,'rotation-two')];let calls=0;
 const fetcher=async()=>({ok:true,json:async()=>({keys:++calls===1?[keys[0]]:keys})});const nonce='rotation-nonce',aud='house.thezoo.babytrack';
 function token(pair,kid){const h=Buffer.from(JSON.stringify({alg:'RS256',kid})).toString('base64url');const c=Buffer.from(JSON.stringify({iss:'https://appleid.apple.com',sub:'rotation-user',aud,iat:Date.now()/1000,exp:Date.now()/1000+300,nonce:hash(nonce)})).toString('base64url');return h+'.'+c+'.'+sign('RSA-SHA256',Buffer.from(h+'.'+c),pair.privateKey).toString('base64url');}
 assert.equal(await verifyApple(token(first,keys[0].kid),nonce,aud,fetcher),'rotation-user');
 assert.equal(await verifyApple(token(second,keys[1].kid),nonce,aud,fetcher),'rotation-user');assert.equal(calls,2);
});
