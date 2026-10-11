import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Store} from './store.mjs';
import {reminderDue,nextRepeat} from './reminders.mjs';
import {historicalSummaries} from './domain.mjs';
const cmd=(entity,action='upsert')=>({id:randomUUID(),action,entity,baseVersion:entity.version??0});
function fixture(t){const s=new Store();t.after(()=>s.close());const user=s.account('feature-user','Synthetic');s.command(user,cmd({id:'child',type:'child',title:'Child',at:1700000000,fields:{}}));return {s,user};}
const reminder=(at)=>({id:'reminder',type:'reminder',title:'Bottle reminder',childID:'child',at,fields:{kind:'feeding',trigger:'After last log',afterHours:'2',recipients:'Only me'}});

test('relative reminders follow matching child logs and keep private recipients',t=>{
 const {s,user}=fixture(t);const now=Date.now()/1000;
 s.command(user,cmd({id:'bottle',type:'feeding',title:'Bottle',childID:'child',at:now-1800,fields:{amount:'4',unit:'oz'}}));
 s.command(user,cmd(reminder(now)));let e=s.list(user.family).find(x=>x.id==='reminder');
 assert.equal(e.at,now+5400);assert.equal(e.recipientUserID,user.id);
 s.command(user,cmd({id:'next-bottle',type:'feeding',title:'Bottle',childID:'child',at:now,fields:{amount:'5',unit:'oz'}}));
 e=s.list(user.family).find(x=>x.id==='reminder');assert.equal(e.at,now+7200);assert.equal(e.version,2);
 assert.equal(s.db.prepare('SELECT count(*) AS n FROM jobs WHERE json_extract(body,\'$.entity.id\')=?').get(e.id).n,1);
});

test('snooze is durable and Done removes all pending deliveries',t=>{
 const {s,user}=fixture(t);const now=Date.now()/1000;s.command(user,cmd({...reminder(now),fields:{kind:'feeding',trigger:'At time',recipients:'All caregivers'}}));
 let e=s.list(user.family).find(x=>x.id==='reminder');s.command(user,cmd({...e,at:now+900},'reminderSnooze'));e=s.list(user.family).find(x=>x.id==='reminder');assert.equal(e.snoozedUntil,now+900);
 s.command(user,cmd({...e,fields:{...e.fields,notes:'Changed notes'}}));e=s.list(user.family).find(x=>x.id==='reminder');assert.equal(e.snoozedUntil,now+900);
 s.command(user,cmd(e,'reminderDone'));assert.equal(s.list(user.family).find(x=>x.id==='reminder').fields.done,'true');assert.equal(s.db.prepare('SELECT count(*) AS n FROM jobs').get().n,0);
});

test('an offline Snooze cannot reopen a reminder another caregiver completed',t=>{
 const {s,user}=fixture(t);const now=Date.now()/1000;s.command(user,cmd({...reminder(now),fields:{kind:'feeding',trigger:'At time'}}));
 const stale=s.list(user.family).find(x=>x.id==='reminder');s.command(user,cmd(stale,'reminderDone'));
 s.command(user,cmd({...stale,at:now+900},'reminderSnooze'));
 assert.equal(s.list(user.family).find(x=>x.id==='reminder').fields.done,'true');assert.equal(s.db.prepare('SELECT count(*) AS n FROM jobs').get().n,0);
});

test('relative medication rules match names without crossing children or using future entries',()=>{
 const e={...reminder(1000),createdAt:500,fields:{kind:'medication',trigger:'After last log',anchorTitle:' Example ',afterHours:'1'}};
 const records=[{type:'medication',childID:'child',title:'example',at:800},{type:'medication',childID:'other',title:'Example',at:950},{type:'medication',childID:'child',title:'Example',at:1100},{type:'medication',childID:'child',title:'Other',at:980}];
 assert.equal(reminderDue(e,records,1000),4400);assert.equal(reminderDue({...e,fields:{...e.fields,done:'true'}},records,1000),null);
 assert.equal(nextRepeat({...e,at:100,fields:{repeatHours:'1'}},4000),7300);
});

test('historical day totals remain consecutive across spring and fall DST',()=>{
 for(const instant of ['2026-03-10T00:15:00-04:00','2026-11-03T00:15:00-05:00']){
  const now=Date.parse(instant)/1000,days=historicalSummaries([],'child',now,'America/New_York',4).map(s=>s.day);
  const first=instant.slice(0,10);const expected=Array.from({length:4},(_,i)=>{const d=new Date(first+'T12:00:00Z');d.setUTCDate(d.getUTCDate()-(i+1));return d.toISOString().slice(0,10);});
  assert.deepEqual(days,expected);
 }
});
