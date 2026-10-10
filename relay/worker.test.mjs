import test from 'node:test';
import assert from 'node:assert/strict';
import { payload,tick } from './worker.mjs';
import { Store } from '../server/store.mjs';
test('sleep start and end use the matching device token',()=>{const entity={id:'session',at:1700000000,childID:'child',end:null};const device={startToken:'start',activityToken:'activity',activityID:'session'};assert.equal(payload({type:'sleep',entity},device,'Sample').body.aps.event,'update');assert.equal(payload({type:'sleep',entity},{startToken:'start'},'Sample').body.aps.event,'start');assert.equal(payload({type:'sleep',entity:{...entity,end:1700003600}},device,'Sample').token,'activity');assert.equal(payload({type:'sleep',entity:{...entity,end:1700003600}},{startToken:'start'},'Sample'),null);});
test('missing APNs setup retains jobs and stale reminders do not send',async t=>{const s=new Store();t.after(()=>s.close());const a=s.authenticate(s.login('synthetic','Sample').token);const entity={id:'reminder',type:'reminder',title:'Bottle reminder',at:1700000000,childID:'child',fields:{kind:'feeding'},version:1,deleted:false};s.put(a.family,entity);s.enqueue({type:'reminder',family:a.family,entity},1);assert.equal((await tick(s,{},()=>{})).configured,false);assert.equal(s.db.prepare('SELECT count(*) as n FROM jobs').get().n,1);s.put(a.family,{...entity,version:2,deleted:true});let sent=false;await tick(s,{keyID:'synthetic',keyPath:'synthetic',teamID:'synthetic'},async()=>{sent=true;return {status:200};});assert.equal(sent,false);assert.equal(s.db.prepare('SELECT count(*) as n FROM jobs').get().n,0);});
test('a retry only resends to devices that have not acknowledged delivery',async t=>{
 const s=new Store();t.after(()=>s.close());const user=s.authenticate(s.login('synthetic-retry','Sample').token);const entity={id:'reminder',type:'reminder',title:'Check bottle',at:1,childID:'child',version:1,deleted:false,fields:{kind:'feeding'}};s.put(user.family,entity);s.enqueue({type:'reminder',family:user.family,entity},1);
 for(const id of ['one','two'])s.db.prepare('INSERT INTO devices VALUES (?,?,?)').run(user.id,id,JSON.stringify({id,enabled:true,pushToken:id}));
 const sent=[];const sender=async(message)=>{sent.push(message.token);return {status:message.token==='two'&&sent.filter(x=>x==='two').length===1?503:200};};
 const credentials={keyID:'synthetic',keyPath:'synthetic',teamID:'synthetic'};await tick(s,credentials,sender,100);await tick(s,credentials,sender,200);assert.deepEqual(sent,['one','two','two']);assert.equal(s.db.prepare('SELECT count(*) as n FROM jobs').get().n,0);
});


test('permanent device failures do not block family reminders and repeats stay anchored',async t=>{
 const store=new Store();t.after(()=>store.close());const user=store.account('review-reminder-owner');
 const entity={id:'repeat',type:'reminder',childID:'child',title:'Synthetic reminder',at:100,version:1,deleted:false,fields:{kind:'feeding',repeatHours:'1'}};
 store.put(user.family,entity);store.enqueue({type:'reminder',family:user.family,entity},100);
 for(const id of ['bad','good'])store.db.prepare('INSERT INTO devices VALUES (?,?,?)').run(user.id,id,JSON.stringify({enabled:true,pushToken:id}));
 const sent=[];await tick(store,{keyID:'test',keyPath:'test',teamID:'test'},async m=>{sent.push(m.token);return {status:m.token==='bad'?403:200};},4000);
 assert.deepEqual(sent,['bad','good']);assert.equal(store.db.prepare('SELECT due FROM jobs').get().due,7300);
});

test('legacy stale membership never receives pushes for another household',async t=>{
 const store=new Store();t.after(()=>store.close());const owner=store.account('review-family-owner'),departed=store.account('review-departed');
 store.db.prepare('INSERT INTO members VALUES (?,?)').run(owner.family,departed.id);
 store.db.prepare('INSERT INTO devices VALUES (?,?,?)').run(departed.id,'phone',JSON.stringify({enabled:true,pushToken:'departed'}));
 const entity={id:'private-reminder',type:'reminder',title:'Private',childID:'child',at:1,version:1,fields:{},deleted:false};store.put(owner.family,entity);store.enqueue({type:'reminder',family:owner.family,entity},1);
 const sent=[];await tick(store,{keyID:'test',keyPath:'test',teamID:'test'},async m=>{sent.push(m.token);return {status:200};},100);
 assert.deepEqual(sent,[]);
});
