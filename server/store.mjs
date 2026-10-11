import { planNara } from './nara.mjs';
import { reminderDue } from './reminders.mjs';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { validateEntity, decorate, summary, historicalSummaries, fail, seedEntities, feedingPreferences, validatePhoto, requiresChild } from './domain.mjs';
export const hash=value=>createHash('sha256').update(value).digest('hex');
export class Store {
 constructor(path=':memory:'){
  this.db=new DatabaseSync(path,{timeout:5000});this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
   CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT NOT NULL, family TEXT NOT NULL, preview INTEGER NOT NULL DEFAULT 0);
   CREATE TABLE IF NOT EXISTS members (family TEXT NOT NULL, user TEXT NOT NULL REFERENCES users(id), PRIMARY KEY(family,user));
   CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, user TEXT NOT NULL REFERENCES users(id), expires REAL NOT NULL);
   CREATE TABLE IF NOT EXISTS entities (family TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(family,id));
   CREATE TABLE IF NOT EXISTS operations (family TEXT NOT NULL, user TEXT NOT NULL, id TEXT NOT NULL, result TEXT NOT NULL, PRIMARY KEY(family,user,id));
   CREATE TABLE IF NOT EXISTS invites (token TEXT PRIMARY KEY, family TEXT NOT NULL, expires REAL NOT NULL, preview INTEGER NOT NULL);
   CREATE TABLE IF NOT EXISTS caregiver_profiles (user TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE, photo TEXT);
   CREATE TABLE IF NOT EXISTS challenges (nonce TEXT PRIMARY KEY, expires REAL NOT NULL);
   CREATE TABLE IF NOT EXISTS devices (user TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(user,id));
   CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, body TEXT NOT NULL, due REAL NOT NULL, attempts INTEGER NOT NULL DEFAULT 0);
   CREATE TABLE IF NOT EXISTS deliveries (job TEXT NOT NULL, user TEXT NOT NULL, device TEXT NOT NULL, PRIMARY KEY(job,user,device));
   PRAGMA user_version=1;`);
  this.transaction(()=>{if(!this.db.prepare('PRAGMA table_info(users)').all().some(c=>c.name==='createdAt')){this.db.exec('ALTER TABLE users ADD COLUMN createdAt REAL NOT NULL DEFAULT 0');this.db.prepare('UPDATE users SET createdAt=? WHERE createdAt=0').run(Date.now()/1000);}});
 }
 transaction(fn){this.db.exec('BEGIN IMMEDIATE');try{const value=fn();this.db.exec('COMMIT');return value;}catch(e){this.db.exec('ROLLBACK');throw e;}}
 account(id,name='Caregiver',preview=false){
  let user=this.db.prepare('SELECT * FROM users WHERE id=?').get(id);
  if(!user){user={id,name,family:randomUUID(),preview:Number(preview)};this.db.prepare('INSERT INTO users(id,name,family,preview,createdAt) VALUES (?,?,?,?,?)').run(id,name,user.family,user.preview,Date.now()/1000);this.db.prepare('INSERT INTO members VALUES (?,?)').run(user.family,id);}
  return user;
 }
 login(id,name,preview=false){const user=this.account(id,name,preview);const token=randomBytes(32).toString('base64url');this.db.prepare('INSERT INTO sessions VALUES (?,?,?)').run(hash(token),id,Date.now()/1000+86400*30);return {token,user:{id:user.id,name:user.name,preview:!!user.preview,photo:this.db.prepare('SELECT photo FROM caregiver_profiles WHERE user=?').get(user.id)?.photo??null}};}
 authenticate(token){const row=this.db.prepare('SELECT users.* FROM sessions JOIN users ON users.id=sessions.user WHERE token=? AND expires>?').get(hash(token??''),Date.now()/1000);if(!row||!this.db.prepare('SELECT 1 FROM members WHERE family=? AND user=?').get(row.family,row.id))fail('Sign in again',401);return row;}
 list(family){return this.db.prepare('SELECT body FROM entities WHERE family=?').all(family).map(r=>JSON.parse(r.body));}
 put(family,e){this.db.prepare('INSERT INTO entities VALUES (?,?,?) ON CONFLICT(family,id) DO UPDATE SET body=excluded.body').run(family,e.id,JSON.stringify(e));}
 stamp(user,entity,previous=null,now=Date.now()/1000){
  const actor=previous?(previous.actor??''):entity.imported?(entity.actor??''):(entity.actor||user.name);
  return {...entity,version:(previous?.version??0)+1,updatedAt:now,createdAt:previous?.createdAt??now,actor,updatedBy:user.name,updatedByID:user.id};
 }
 snapshot(user,timeZone,{includeSource=false}={}){const all=this.list(user.family);const entities=all.filter(e=>!e.deleted).map(e=>{const result=decorate(e,all);if(result.imported&&!includeSource)result.imported={...result.imported,raw:{}};return result;}).sort((a,b)=>b.at-a.at||a.id.localeCompare(b.id));const children=entities.filter(e=>e.type==='child');const now=Date.now()/1000;return {version:1,familyID:user.family,serverTime:now,entities,summaries:children.map(e=>summary(all,e.id,now,timeZone)),daySummaries:children.flatMap(e=>historicalSummaries(all,e.id,now,timeZone)),...feedingPreferences(all),members:this.db.prepare('SELECT users.id,users.name,caregiver_profiles.photo FROM members JOIN users ON users.id=members.user LEFT JOIN caregiver_profiles ON caregiver_profiles.user=users.id WHERE members.family=? AND users.family=members.family').all(user.family),user:{id:user.id,name:user.name,preview:!!user.preview,photo:this.db.prepare('SELECT photo FROM caregiver_profiles WHERE user=?').get(user.id)?.photo??null}};}
 source(user,id){const record=this.list(user.family).find(e=>e.id===id&&!e.deleted);if(!record?.imported)fail('Original import data is not available',404);return record.imported;}
 updateCaregiver(user,body){
  if(!body||!Object.hasOwn(body,'photo'))fail('Choose a profile photo');
  if(Object.keys(body).some(k=>!['photo','timeZone'].includes(k)))fail('Only your own profile can be changed');
  if(body.photo!==null)validatePhoto(body.photo);
  this.db.prepare('INSERT INTO caregiver_profiles(user,photo) VALUES (?,?) ON CONFLICT(user) DO UPDATE SET photo=excluded.photo').run(user.id,body.photo);
  return this.snapshot(user,body.timeZone);
 }
 preview(){const id='preview-'+randomUUID();const login=this.login(id,'Alex',true);const user=this.authenticate(login.token);for(const e of seedEntities())this.put(user.family,e);return {...login,snapshot:this.snapshot(user)};}
 expirePreviews(now=Date.now()/1000){for(const user of this.db.prepare('SELECT * FROM users WHERE preview=1 AND createdAt<?').all(now-86400))this.deleteAccount(user);}
 issueChallenge(){const nonce=randomBytes(32).toString('base64url');this.db.prepare('DELETE FROM challenges WHERE expires<?').run(Date.now()/1000);this.db.prepare('INSERT INTO challenges VALUES (?,?)').run(hash(nonce),Date.now()/1000+300);return nonce;}
 validChallenge(nonce){return typeof nonce==='string'&&!!this.db.prepare('SELECT 1 FROM challenges WHERE nonce=? AND expires>?').get(hash(nonce),Date.now()/1000);}
 consumeChallenge(nonce,id,name){return this.transaction(()=>{if(this.db.prepare('DELETE FROM challenges WHERE nonce=? AND expires>?').run(hash(nonce),Date.now()/1000).changes!==1)fail('Sign-in session was already used',401);return this.login(id,name);});}
 logout(token){this.db.prepare('DELETE FROM sessions WHERE token=?').run(hash(token));}
 registerDevice(user,body){
  if(typeof body.id!=='string'||body.id.length>100||!body.id)fail('Invalid device');
  const tokens=['pushToken','startToken','activityToken'];for(const key of tokens)if(body[key]!=null&&(typeof body[key]!=='string'||!/^([a-f0-9]{2}){16,128}$/.test(body[key])))fail('Invalid push token');
  const data={id:body.id,enabled:!!body.enabled,environment:body.environment==='production'?'production':'sandbox'};
  for(const field of [...tokens,'activityID'])if(body[field]!=null)data[field]=String(body[field]).slice(0,field==='activityID'?80:256);
  const old=this.db.prepare('SELECT body FROM devices WHERE user=? AND id=?').get(user.id,data.id),merged={...(old?JSON.parse(old.body):{}),...data};
  if(data.activityID&&data.activityToken){merged.activityTokens={...(merged.activityTokens??{}),[data.activityID]:data.activityToken};merged.activityTokens=Object.fromEntries(Object.entries(merged.activityTokens).slice(-32));}
  this.saveDevice(user.id,data.id,merged);
 }
 saveDevice(user,id,device){this.db.prepare('INSERT INTO devices VALUES (?,?,?) ON CONFLICT(user,id) DO UPDATE SET body=excluded.body').run(user,id,JSON.stringify(device));}
 deliveryRecipients(family,onlyUser=null){return this.db.prepare('SELECT devices.user,devices.id,devices.body FROM devices JOIN members ON devices.user=members.user JOIN users ON users.id=members.user WHERE members.family=? AND users.family=members.family').all(family).filter(r=>!onlyUser||r.user===onlyUser);}
 jobsDue(now){return this.db.prepare('SELECT * FROM jobs WHERE due<=? ORDER BY due LIMIT 30').all(now);}
 delivered(job,user,device){return !!this.db.prepare('SELECT 1 FROM deliveries WHERE job=? AND user=? AND device=?').get(job,user,device);}
 markDelivered(job,user,device){this.db.prepare('INSERT OR IGNORE INTO deliveries VALUES (?,?,?)').run(job,user,device);}
 retryJob(id,due){this.db.prepare('UPDATE jobs SET attempts=attempts+1,due=? WHERE id=?').run(due,id);}
 removeJob(id){this.transaction(()=>{this.db.prepare('DELETE FROM deliveries WHERE job=?').run(id);this.db.prepare('DELETE FROM jobs WHERE id=?').run(id);});}
 command(user,command){
  if(!command||typeof command.id!=='string'||!/^[-\w]{1,80}$/.test(command.id))fail('Invalid operation ID');
  if(!['upsert','delete','sleepStart','sleepStop','reminderDone','reminderSnooze'].includes(command.action))fail('Invalid operation');
  return this.transaction(()=>{
   const old=this.db.prepare('SELECT result FROM operations WHERE family=? AND user=? AND id=?').get(user.family,user.id,command.id);if(old)return JSON.parse(old.result);
   const all=this.list(user.family);const previous=all.find(e=>e.id===command.entity?.id);
   let entity;
   if(command.action==='delete'){
    if(!previous)fail('Record no longer exists',404);
    if((command.baseVersion??0)!==previous.version){const result={id:command.id,status:'conflict',message:'This record changed on another device. The latest version has been loaded.',entityID:previous.id};this.saveOperation(user,command,result);return result;}
    entity={...previous,deleted:true};
   }else if(['reminderDone','reminderSnooze'].includes(command.action)){
    if(!previous||previous.deleted||previous.type!=='reminder')fail('Reminder is no longer available',404);
    if(command.action==='reminderSnooze'&&previous.fields.done==='true'){const result={id:command.id,status:'accepted',entityID:previous.id};this.saveOperation(user,command,result);return result;}
    if(command.action==='reminderDone')entity={...previous,fields:{...previous.fields,done:'true'}};
    else{const until=command.entity?.at;if(!Number.isFinite(until)||until<=Date.now()/1000||until>Date.now()/1000+86400*7)fail('Choose a snooze within the next seven days');entity={...previous,at:until,snoozedUntil:until,fields:{...previous.fields,done:'false'}};}
   }else if(command.action==='sleepStop'){
    if(!previous||previous.deleted||previous.type!=='sleep')fail('Sleep session no longer exists',409);
    if(previous.end!=null){const result={id:command.id,status:'accepted',entityID:previous.id};this.saveOperation(user,command,result);return result;}
    const end=command.entity?.end;if(!Number.isFinite(end)||end<previous.at||end-previous.at>86400*7||end>Date.now()/1000+120)fail('Check the sleep end date');
    entity={...previous,end};
   }else{
    let input=command.entity;
    if(input?.type==='feeding'&&command.action==='upsert'&&!Object.hasOwn(input.fields??{},'brand')){
     const preferred=feedingPreferences(all).feedingDefaults.find(d=>d.childID===input.childID)?.formula;
     if(preferred)input={...input,fields:{...input.fields,brand:preferred}};
    }
    entity=validateEntity(input,{imported:!!previous?.imported});
    if(previous?.imported)entity.imported=previous.imported;
    if(entity.type==='formula'){
     const existing=all.find(e=>!e.deleted&&e.type==='formula'&&e.title.toLocaleLowerCase('en-US')===entity.title.toLocaleLowerCase('en-US')&&e.id!==entity.id);
     if(existing&&command.action==='upsert'){const result={id:command.id,status:'accepted',entityID:existing.id};this.saveOperation(user,command,result);return result;}
    }
    if(previous&&previous.type!==entity.type)fail('Record type cannot change');
    if(previous&&(command.baseVersion??0)!==previous.version){const result={id:command.id,status:'conflict',message:'This record changed on another device. The latest version has been loaded.',entityID:previous.id};this.saveOperation(user,command,result);return result;}
    if(entity.type==='sleep'&&command.action==='upsert'){
     if(entity.end==null&&(!previous||previous.deleted||previous.end!=null))fail('Start sleep using the shared sleep timer');
     if(previous&&!previous.deleted&&previous.end==null&&entity.end!=null)fail('End sleep using the shared sleep timer');
    }
    if(command.action==='sleepStart'){
     if(entity.type!=='sleep'||entity.end!=null)fail('Invalid sleep start');
     if(previous&&(previous.deleted||previous.end!=null))fail('Start a new sleep session');
     const active=all.find(e=>!e.deleted&&e.type==='sleep'&&e.childID===entity.childID&&e.end==null);
     if(active){const result={id:command.id,status:'conflict',message:'A caregiver already started sleep. The shared timer has been loaded.',entityID:active.id,requestedEntityID:entity.id};this.saveOperation(user,command,result);return result;}
    }
   }
   if(!entity.deleted&&requiresChild(entity.type)&&!all.some(e=>e.id===entity.childID&&e.type==='child'&&!e.deleted))fail('Choose a child in this family');
   for(const field of entity.deleted?[]:['locationID','parentID','itemID']){const id=entity.fields[field];if(id&&!all.some(e=>e.id===id&&!e.deleted&&(field==='itemID'?e.type==='book':e.type==='location')))fail('Referenced item is not in this family');}
   if(entity.type==='location'&&!entity.deleted){
    let parent=entity.fields.parentID;const seen=new Set([entity.id]);while(parent){if(seen.has(parent))fail('A location cannot contain itself');seen.add(parent);parent=all.find(e=>e.id===parent)?.fields.parentID;}
   }
   if(entity.deleted&&all.some(e=>!e.deleted&&e.id!==entity.id&&(e.childID===entity.id||e.fields.locationID===entity.id||e.fields.parentID===entity.id||e.fields.itemID===entity.id)))fail('Move or remove linked records first');
   const now=Date.now()/1000;
   entity=this.stamp(user,entity,previous,now);
   if(entity.type==='reminder'){
    if(command.action==='upsert'&&previous?.at===entity.at)entity.snoozedUntil=previous.snoozedUntil;
    entity.recipientUserID=entity.fields.recipients==='Only me'?(previous?.fields.recipients==='Only me'?previous.recipientUserID??user.id:user.id):null;
    if(entity.fields.trigger==='After last log')entity.at=reminderDue(entity,all,now)??entity.at;
    this.clearEntityJobs(user.family,entity.id);
   }
   this.put(user.family,entity);
   const result={id:command.id,status:'accepted',entityID:entity.id};this.saveOperation(user,command,result);
   if(entity.type==='sleep'){this.enqueue({type:'sleep',family:user.family,entity},Date.now()/1000);}
   if(entity.type==='reminder'&&reminderDue(entity,all,now)!=null)this.enqueue({type:'reminder',family:user.family,entity},entity.at);
   if(['feeding','medication'].includes(entity.type))this.rescheduleReminders(user.family,entity,user,now);
   return result;
 });
 }
 clearEntityJobs(family,id){this.db.prepare('DELETE FROM deliveries WHERE job IN (SELECT id FROM jobs WHERE json_extract(body,\'$.family\')=? AND json_extract(body,\'$.entity.id\')=?)').run(family,id);this.db.prepare('DELETE FROM jobs WHERE json_extract(body,\'$.family\')=? AND json_extract(body,\'$.entity.id\')=?').run(family,id);}
 rescheduleReminders(family,changed,user,now){
  const all=this.list(family);
  for(const previous of all.filter(e=>e.type==='reminder'&&!e.deleted&&e.fields.done!=='true'&&e.fields.trigger==='After last log'&&e.childID===changed.childID&&e.fields.kind===changed.type)){
   const due=reminderDue(previous,all,now);if(due===previous.at)continue;
   const entity=this.stamp(user,{...previous,at:due},previous,now);
   this.put(family,entity);this.clearEntityJobs(family,entity.id);this.enqueue({type:'reminder',family,entity},due);
  }
 }
 sync(user,commands,timeZone,familyID){
  if(familyID!==undefined&&familyID!==user.family)fail('Your family changed. Reconnect before syncing these records.',409);
  if(!Array.isArray(commands)||commands.length>50)fail('Send at most 50 operations');
  const aliases=new Map();const results=[];
  for(const original of commands){
   let command=original;
   if(command?.action==='sleepStop'){
    const target=aliases.get(command.entity?.id);
    if(target){const active=this.list(user.family).find(e=>e.id===target);if(active&&command.entity.end<active.at){const result={id:command.id,status:'conflict',message:'A newer sleep started after this stop. The shared timer has been loaded.',entityID:target};this.transaction(()=>this.saveOperation(user,command,result));results.push(result);continue;}command={...command,entity:{...command.entity,id:target}};}
   }
   try{const result=this.command(user,command);results.push(result);if(original.action==='sleepStart'&&result.status==='conflict'&&result.entityID)aliases.set(original.entity.id,result.entityID);}
   catch(error){if(!error.status||error.status>=500)throw Object.assign(new Error('The server is busy. Your changes are still waiting to sync.'),{status:503});results.push({id:command?.id??'',status:'rejected',message:error.message});}
  }
  return {results,snapshot:this.snapshot(user,timeZone)};
 }
 importNara(user,{csv,familyID,targetChildID='',commit=false,timeZone}){
  if(familyID!==user.family)fail('The family changed. Preview the import again.',409);
  const run=()=>{const report=planNara(csv,{familyID:user.family,existing:this.list(user.family),targetChildID});
   if(commit){for(const e of report.records)this.put(user.family,this.stamp(user,e));}
   return {...report,records:undefined,...(commit?{snapshot:this.snapshot(user,timeZone)}:{})};};
  return commit?this.transaction(run):run();
 }
 saveOperation(user,command,result){this.db.prepare('INSERT INTO operations VALUES (?,?,?,?)').run(user.family,user.id,command.id,JSON.stringify(result));}
 invite(user){const token=randomBytes(24).toString('base64url');this.db.prepare('INSERT INTO invites VALUES (?,?,?,?)').run(hash(token),user.family,Date.now()/1000+86400*7,user.preview);return {code:token,expiresAt:Date.now()/1000+86400*7};}
 join(user,code){return this.transaction(()=>{const invite=this.db.prepare('SELECT * FROM invites WHERE token=? AND expires>?').get(hash(code),Date.now()/1000);if(!invite)fail('This invitation expired or was already used',404);if(invite.preview!==user.preview)fail('Sample families cannot join real families',403);this.db.prepare('DELETE FROM invites WHERE token=?').run(hash(code));return this.#moveMember(user,invite.family);});}
 restorePreviewFamily(user,family){if(!user.preview||typeof family!=='string'||!/^[-\w]{1,80}$/.test(family))fail('Only a private preview can restore its family');return this.transaction(()=>this.#moveMember(user,family));}
 #moveMember(user,family){const old=this.db.prepare('SELECT family FROM members WHERE user=? AND family<>?').all(user.id,family).map(x=>x.family);this.db.prepare('DELETE FROM members WHERE user=? AND family<>?').run(user.id,family);this.db.prepare('INSERT OR IGNORE INTO members VALUES (?,?)').run(family,user.id);this.db.prepare('UPDATE users SET family=? WHERE id=?').run(family,user.id);for(const previous of old)this.removeEmptyFamily(previous);return this.authenticateFromID(user.id);}
 removeEmptyFamily(family){
  if(this.db.prepare('SELECT 1 FROM members JOIN users ON users.id=members.user WHERE members.family=? AND users.family=members.family').get(family))return;
  this.db.prepare('DELETE FROM deliveries WHERE job IN (SELECT id FROM jobs WHERE json_extract(body,\'$.family\')=?)').run(family);
  this.db.prepare('DELETE FROM jobs WHERE json_extract(body,\'$.family\')=?').run(family);
  this.db.prepare('DELETE FROM members WHERE family=?').run(family);
  for(const table of ['entities','operations','invites'])this.db.prepare(`DELETE FROM ${table} WHERE family=?`).run(family);
 }
 deleteAccount(user){this.transaction(()=>{const families=new Set([user.family,...this.db.prepare('SELECT family FROM members WHERE user=?').all(user.id).map(x=>x.family)]);for(const table of ['sessions','devices','members','deliveries','operations'])this.db.prepare(`DELETE FROM ${table} WHERE user=?`).run(user.id);this.db.prepare('DELETE FROM users WHERE id=?').run(user.id);for(const family of families)this.removeEmptyFamily(family);});}
 authenticateFromID(id){return this.db.prepare('SELECT * FROM users WHERE id=?').get(id);}
 enqueue(body,due){this.db.prepare('INSERT INTO jobs VALUES (?,?,?,0)').run(randomUUID(),JSON.stringify(body),due);}
 close(){this.db.close();}
}
