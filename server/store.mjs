import { planNara } from './nara.mjs';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { validateEntity, decorate, summary, fail, seedEntities, feedingPreferences, validatePhoto } from './domain.mjs';
export const hash=value=>createHash('sha256').update(value).digest('hex');
export class Store {
 constructor(path=':memory:'){
  this.db=new DatabaseSync(path);this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
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
 }
 transaction(fn){this.db.exec('BEGIN IMMEDIATE');try{const value=fn();this.db.exec('COMMIT');return value;}catch(e){this.db.exec('ROLLBACK');throw e;}}
 account(id,name='Caregiver',preview=false){
  let user=this.db.prepare('SELECT * FROM users WHERE id=?').get(id);
  if(!user){user={id,name,family:randomUUID(),preview:Number(preview)};this.db.prepare('INSERT INTO users VALUES (?,?,?,?)').run(id,name,user.family,user.preview);this.db.prepare('INSERT INTO members VALUES (?,?)').run(user.family,id);}
  return user;
 }
 login(id,name,preview=false){const user=this.account(id,name,preview);const token=randomBytes(32).toString('base64url');this.db.prepare('INSERT INTO sessions VALUES (?,?,?)').run(hash(token),id,Date.now()/1000+86400*30);return {token,user:{id:user.id,name:user.name,preview:!!user.preview,photo:this.db.prepare('SELECT photo FROM caregiver_profiles WHERE user=?').get(user.id)?.photo??null}};}
 authenticate(token){const row=this.db.prepare('SELECT users.* FROM sessions JOIN users ON users.id=sessions.user WHERE token=? AND expires>?').get(hash(token??''),Date.now()/1000);if(!row||!this.db.prepare('SELECT 1 FROM members WHERE family=? AND user=?').get(row.family,row.id))fail('Sign in again',401);return row;}
 list(family){return this.db.prepare('SELECT body FROM entities WHERE family=?').all(family).map(r=>JSON.parse(r.body));}
 put(family,e){this.db.prepare('INSERT INTO entities VALUES (?,?,?) ON CONFLICT(family,id) DO UPDATE SET body=excluded.body').run(family,e.id,JSON.stringify(e));}
 snapshot(user,timeZone){const all=this.list(user.family);const entities=all.filter(e=>!e.deleted).map(e=>decorate(e,all)).sort((a,b)=>b.at-a.at||a.id.localeCompare(b.id));const children=entities.filter(e=>e.type==='child');return {version:1,familyID:user.family,serverTime:Date.now()/1000,entities,summaries:children.map(e=>summary(all,e.id,Date.now()/1000,timeZone)),...feedingPreferences(all),members:this.db.prepare('SELECT users.id,users.name,caregiver_profiles.photo FROM members JOIN users ON users.id=members.user LEFT JOIN caregiver_profiles ON caregiver_profiles.user=users.id WHERE members.family=?').all(user.family),user:{id:user.id,name:user.name,preview:!!user.preview,photo:this.db.prepare('SELECT photo FROM caregiver_profiles WHERE user=?').get(user.id)?.photo??null}};}
 updateCaregiver(user,body){
  if(!body||!Object.hasOwn(body,'photo'))fail('Choose a profile photo');
  if(Object.keys(body).some(k=>!['photo','timeZone'].includes(k)))fail('Only your own profile can be changed');
  if(body.photo!==null)validatePhoto(body.photo);
  this.db.prepare('INSERT INTO caregiver_profiles(user,photo) VALUES (?,?) ON CONFLICT(user) DO UPDATE SET photo=excluded.photo').run(user.id,body.photo);
  return this.snapshot(user,body.timeZone);
 }
 preview(){const id='preview-'+randomUUID();const login=this.login(id,'Alex',true);const user=this.authenticate(login.token);for(const e of seedEntities())this.put(user.family,e);return {...login,snapshot:this.snapshot(user)};}
 command(user,command){
  if(!command||typeof command.id!=='string'||!/^[-\w]{1,80}$/.test(command.id))fail('Invalid operation ID');
  if(!['upsert','delete','sleepStart','sleepStop'].includes(command.action))fail('Invalid operation');
  return this.transaction(()=>{
   const old=this.db.prepare('SELECT result FROM operations WHERE family=? AND user=? AND id=?').get(user.family,user.id,command.id);if(old)return JSON.parse(old.result);
   const all=this.list(user.family);const previous=all.find(e=>e.id===command.entity?.id);
   let entity;
   if(command.action==='sleepStop'){
    if(!previous||previous.deleted||previous.type!=='sleep')fail('Sleep session no longer exists',409);
    if(previous.end!=null){const result={id:command.id,status:'accepted',entityID:previous.id};this.saveOperation(user,command,result);return result;}
    const end=command.entity?.end;if(!Number.isFinite(end)||end<previous.at||end-previous.at>86400*7)fail('Check the sleep end date');
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
    if(command.action==='delete'){if(!previous)fail('Record no longer exists',404);entity={...previous,deleted:true};}
    if(command.action==='sleepStart'){
     if(entity.type!=='sleep'||entity.end!=null)fail('Invalid sleep start');
     const active=all.find(e=>!e.deleted&&e.type==='sleep'&&e.childID===entity.childID&&e.end==null);
     if(active){const result={id:command.id,status:'conflict',message:'A caregiver already started sleep. The shared timer has been loaded.',entityID:active.id};this.saveOperation(user,command,result);return result;}
    }
   }
   if(!['child','location','book','toy','clothing','formula'].includes(entity.type)&&!all.some(e=>e.id===entity.childID&&e.type==='child'&&!e.deleted))fail('Choose a child in this family');
   for(const field of ['locationID','parentID','itemID']){const id=entity.fields[field];if(id&&!all.some(e=>e.id===id&&!e.deleted&&(field==='itemID'?e.type==='book':e.type==='location')))fail('Referenced item is not in this family');}
   if(entity.type==='location'){
    let parent=entity.fields.parentID;const seen=new Set([entity.id]);while(parent){if(seen.has(parent))fail('A location cannot contain itself');seen.add(parent);parent=all.find(e=>e.id===parent)?.fields.parentID;}
   }
   if(entity.deleted&&all.some(e=>!e.deleted&&e.id!==entity.id&&(e.childID===entity.id||e.fields.locationID===entity.id||e.fields.parentID===entity.id||e.fields.itemID===entity.id)))fail('Move or remove linked records first');
   entity={...entity,version:(previous?.version??0)+1,updatedAt:Date.now()/1000,actor:previous?.actor||user.name};this.put(user.family,entity);
   const result={id:command.id,status:'accepted',entityID:entity.id};this.saveOperation(user,command,result);
   if(entity.type==='sleep'){this.enqueue({type:'sleep',family:user.family,entity},Date.now()/1000);}
   if(entity.type==='reminder'&&!entity.deleted){this.enqueue({type:'reminder',family:user.family,entity},entity.at);}
   return result;
  });
 }
 importNara(user,{csv,familyID,targetChildID='',commit=false,timeZone}){
  if(familyID!==user.family)fail('The family changed. Preview the import again.',409);
  const run=()=>{const report=planNara(csv,{familyID:user.family,existing:this.list(user.family),targetChildID});
   if(commit){for(const e of report.records)this.put(user.family,{...e,updatedAt:Date.now()/1000});}
   return {...report,records:undefined,...(commit?{snapshot:this.snapshot(user,timeZone)}:{})};};
  return commit?this.transaction(run):run();
 }
 saveOperation(user,command,result){this.db.prepare('INSERT INTO operations VALUES (?,?,?,?)').run(user.family,user.id,command.id,JSON.stringify(result));}
 invite(user){const token=randomBytes(24).toString('base64url');this.db.prepare('INSERT INTO invites VALUES (?,?,?,?)').run(hash(token),user.family,Date.now()/1000+86400*7,user.preview);return {code:token,expiresAt:Date.now()/1000+86400*7};}
 join(user,code){return this.transaction(()=>{const invite=this.db.prepare('SELECT * FROM invites WHERE token=? AND expires>?').get(hash(code),Date.now()/1000);if(!invite)fail('This invitation expired or was already used',404);if(invite.preview!==user.preview)fail('Sample families cannot join real families',403);this.db.prepare('INSERT OR IGNORE INTO members VALUES (?,?)').run(invite.family,user.id);this.db.prepare('UPDATE users SET family=? WHERE id=?').run(invite.family,user.id);this.db.prepare('DELETE FROM invites WHERE token=?').run(hash(code));return this.authenticateFromID(user.id);});}
 authenticateFromID(id){return this.db.prepare('SELECT * FROM users WHERE id=?').get(id);}
 enqueue(body,due){this.db.prepare('INSERT INTO jobs VALUES (?,?,?,0)').run(randomUUID(),JSON.stringify(body),due);}
 close(){this.db.close();}
}
