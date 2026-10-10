import test from 'node:test';
import assert from 'node:assert/strict';
import { summary,decorate } from './domain.mjs';
test('sleep summary clips a session at local midnight including a DST day',()=>{
 const now=Date.parse('2026-03-08T12:00:00-04:00')/1000;
 const entity={id:'synthetic-sleep',type:'sleep',childID:'synthetic-child',at:Date.parse('2026-03-07T23:00:00-05:00')/1000,end:Date.parse('2026-03-08T08:00:00-04:00')/1000,fields:{},deleted:false};
 assert.equal(summary([entity],'synthetic-child',now,'America/New_York').sleepMinutes,420);
});
test('nested location names and upcoming state come from server projection',()=>{
 const entities=[{id:'room',type:'location',title:'Nursery',fields:{},deleted:false},{id:'shelf',type:'location',title:'Shelf',fields:{parentID:'room'},deleted:false}];
 const book={type:'book',at:1,title:'Sample',fields:{author:'Sample Author',locationID:'shelf',status:'Owned'}};
 assert.equal(decorate(book,entities).detail,'Sample Author · Nursery → Shelf · Owned');
 assert.equal(decorate({type:'appointment',at:Date.now()/1000+86400,fields:{}},entities).scheduled,true);
});
test('diaper choices accept combinations and project legacy and explicit flags',async()=>{
 const {validateEntity}=await import('./domain.mjs');
 const input={id:'synthetic-diaper',type:'diaper',title:'Diaper',childID:'synthetic-child',at:1,fields:{contents:'Both',color:'Brown Gray',consistency:'Mucous Mushy',blowout:'true',rash:'true'}};
 assert.equal(validateEntity(input).fields.color,'Brown Gray');
 assert.equal(decorate(input,[]).detail,'Both · Brown Gray · Mucous Mushy · Blowout · Diaper rash');
 assert.throws(()=>validateEntity({...input,fields:{...input.fields,color:'Brown Purple'}}),/Invalid color/);
 assert.throws(()=>validateEntity({...input,fields:{...input.fields,blowout:'yes'}}),/Invalid blowout/);
 const legacy={...input,fields:{contents:'Dirty',detail:'Blowout'}};
 assert.equal(decorate(legacy,[]).detail,'Dirty · Blowout');
 assert.equal(decorate({...legacy,fields:{...legacy.fields,blowout:'false'}},[]).detail,'Dirty');
 assert.equal(validateEntity({...input,fields:{contents:'Dirty',color:'Gray',consistency:'Pebbles'}}).fields.consistency,'Pebbles');
});
