import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Store} from './store.mjs';
import {createServer} from './main.mjs';
import {summary} from './domain.mjs';
import {request} from 'node:http';

const operation=(entity,action='upsert',baseVersion=entity.version??0)=>({id:randomUUID(),entity,action,baseVersion});
const child={id:'review-child',type:'child',title:'Synthetic child',at:1700000000,fields:{},childID:''};
const sleep=(id,end=null)=>({id,type:'sleep',title:'Sleep',at:1700000100,end,fields:{category:'Nap'},childID:child.id});
function fixture(t){const store=new Store();t.after(()=>store.close());const user=store.authenticate(store.login('review-user','Synthetic caregiver').token);store.command(user,operation(child));return {store,user};}

test('a slow upload rechecks membership after the request body arrives',async t=>{
 const {store,user}=fixture(t),login=store.login(user.id),other=store.account('new-household');
 store.join(store.account('old-remaining'),store.invite(user).code);
 const server=createServer(store);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>server.close());
 let seen;const authenticated=new Promise(resolve=>{seen=resolve;});const authenticate=store.authenticate.bind(store);
 store.authenticate=token=>{const result=authenticate(token);if(token===login.token)seen();return result;};
 const body=JSON.stringify({familyID:user.family,commands:[operation({id:'stale-family-write',type:'note',title:'Stale upload',childID:child.id,at:1700000300,fields:{notes:'Synthetic'}})]});
 let upload;const result=new Promise((resolve,reject)=>{
  upload=request({host:'127.0.0.1',port:server.address().port,path:'/v1/sync',method:'POST',headers:{authorization:'Bearer '+login.token,'content-type':'application/json','content-length':Buffer.byteLength(body)}},response=>{response.resume();response.on('end',()=>resolve(response.statusCode));});upload.on('error',reject);
 });
 t.after(()=>upload.destroy());upload.write(body.slice(0,1));await authenticated;
 store.join(user,store.invite(other).code);upload.end(body.slice(1));
 assert.equal(await result,409);
 assert.equal(store.list(user.family).some(e=>e.id==='stale-family-write'),false);
});

test('preview expiry removes old anonymous state and preserves fresh and real households',t=>{
 const {store,user}=fixture(t),old=store.preview(),fresh=store.preview(),now=Date.now()/1000;
 store.db.prepare('UPDATE users SET createdAt=? WHERE id=?').run(now-86401,old.user.id);
 store.enqueue({type:'reminder',family:old.snapshot.familyID,entity:{id:'expired-reminder'}},now);
 store.expirePreviews(now);
 assert.throws(()=>store.authenticate(old.token),/Sign in/);
 assert.equal(store.list(old.snapshot.familyID).length,0);
 assert.equal(store.db.prepare('SELECT count(*) AS n FROM jobs WHERE json_extract(body,\'$.family\')=?').get(old.snapshot.familyID).n,0);
 assert.equal(store.authenticate(fresh.token).id,fresh.user.id);
 assert.equal(store.list(user.family).length,1);
});

test('family join removes the old membership and clears an empty household',t=>{
 const {store,user}=fixture(t);const newcomer=store.account('review-newcomer');const old=newcomer.family;
 store.put(old,{...child,id:'old-profile'});
 store.enqueue({type:'reminder',family:old,entity:{id:'old-reminder'}},0);
 const joined=store.join(newcomer,store.invite(user).code);
 assert.equal(joined.family,user.family);
 assert.deepEqual(store.db.prepare('SELECT family FROM members WHERE user=?').all(newcomer.id).map(x=>x.family),[user.family]);
 assert.equal(store.list(old).length,0);
 assert.equal(store.db.prepare('SELECT count(*) AS n FROM jobs WHERE json_extract(body,\'$.family\')=?').get(old).n,0);
});

test('private preview restoration is atomic and cannot move a real account',t=>{
 const {store,user}=fixture(t);assert.throws(()=>store.restorePreviewFamily(user,'restored-family'),/preview/);
 const preview=store.account('private-preview','You',true);const old=preview.family;
 store.put(old,{...child,id:'starter-child'});
 assert.equal(store.restorePreviewFamily(preview,'restored-family').family,'restored-family');
 assert.equal(store.list(old).length,0);
 assert.deepEqual(store.snapshot(store.authenticateFromID(preview.id)).members.map(x=>x.id),[preview.id]);
});

test('an ordinary upsert cannot create another active sleep or stop an existing one',t=>{
 const {store,user}=fixture(t);store.command(user,operation(sleep('active'),'sleepStart'));
 assert.throws(()=>store.command(user,operation(sleep('extra'))),/sleep/i);
 const active=store.list(user.family).find(x=>x.id==='active');
 assert.equal(store.command(user,operation({...active,fields:{category:'Night'}})).status,'accepted');
 assert.equal(store.list(user.family).find(x=>x.id==='active').end,null);
 assert.throws(()=>store.command(user,operation({...active,version:2,end:1700000700})),/sleep/i);
});

test('new completed sleep cannot end in the future',t=>{
 const {store,user}=fixture(t);const now=Date.now()/1000;
 assert.throws(()=>store.command(user,operation({...sleep('future'),at:now-3600,end:now+3600})),/future|end/i);
});

test('starting sleep cannot reopen a completed or deleted session ID',t=>{
 const {store,user}=fixture(t);store.command(user,operation(sleep('complete',1700000200)));
 const completed=store.list(user.family).find(e=>e.id==='complete');
 assert.throws(()=>store.command(user,operation({...completed,end:null},'sleepStart')),/new sleep/);
 assert.equal(store.list(user.family).find(e=>e.id==='complete').end,1700000200);
});

test('a legacy record can be deleted using its stored data without revalidating old fields',t=>{
 const {store,user}=fixture(t);const legacy={...sleep('legacy',1700000200),fields:{category:'Old option',legacy:'retained'},version:1};store.put(user.family,legacy);
 assert.equal(store.command(user,operation(legacy,'delete')).status,'accepted');
 assert.equal(store.list(user.family).find(x=>x.id===legacy.id).deleted,true);
});

test('today sleep is the union of overlapping intervals, not their sum',()=>{
 const now=Date.parse('2026-10-10T05:00:00Z')/1000;
 const start=Date.parse('2026-10-10T01:00:00Z')/1000;
 const records=[{...sleep('first'),at:start,end:start+7200},{...sleep('second'),at:start+3600,end:start+10800}];
 assert.equal(summary(records,child.id,now,'UTC').sleepMinutes,180);
});

test('transient sync errors preserve retryability instead of rejecting the operation',async t=>{
 const store=new Store();const server=createServer(store,{preview:true});await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 t.after(()=>{server.close();store.close();});const token=store.preview().token;
 store.command=()=>{throw Object.assign(new Error('database is locked'),{code:'SQLITE_BUSY'});};
 const response=await fetch('http://127.0.0.1:'+server.address().port+'/v1/sync',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+token},body:JSON.stringify({commands:[operation({...child,id:'queued-child'})]})});
 assert.equal(response.status,503);
 assert.equal((await response.json()).error,'The server is busy. Your changes are still waiting to sync.');
});


test('offline start then stop resolves to the existing shared sleep in one batch',t=>{
 const {store,user}=fixture(t);store.command(user,operation(sleep('shared'),'sleepStart'));
 const local=sleep('offline');const start=operation(local,'sleepStart'),stop=operation({...local,end:1700001000},'sleepStop');
 const response=store.sync(user,[start,stop],'UTC');
 assert.deepEqual(response.results.map(x=>x.status),['conflict','accepted']);
 assert.equal(store.list(user.family).find(x=>x.id==='shared').end,1700001000);
 assert.deepEqual(store.sync(user,[start,stop],'UTC').results,response.results);
});

test('leaving a household preserves the remaining caregiver and their records',t=>{
 const {store,user}=fixture(t);const owner=store.account('old-owner');const departing=store.join(store.account('departing'),store.invite(owner).code);
 store.put(owner.family,{...child,id:'retained-profile'});
 store.join(departing,store.invite(user).code);
 assert.equal(store.list(owner.family).length,1);
 assert.deepEqual(store.snapshot(owner).members.map(x=>x.id),[owner.id]);
});

test('account deletion also cleans stale memberships without deleting other families',t=>{
 const {store,user}=fixture(t);const other=store.account('other-owner');
 store.db.prepare('INSERT INTO members VALUES (?,?)').run(other.family,user.id);
 store.put(other.family,{...child,id:'other-profile'});
 const token=store.login(user.id).token;store.deleteAccount(user);
 assert.throws(()=>store.authenticate(token),/Sign in/);
 assert.equal(store.list(user.family).length,0);
 assert.equal(store.list(other.family).length,1);
 assert.deepEqual(store.snapshot(other).members.map(x=>x.id),[other.id]);
});
