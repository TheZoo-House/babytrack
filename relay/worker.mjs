import { Store } from '../server/store.mjs';
import { nextRepeat } from '../server/reminders.mjs';
import { readFileSync } from 'node:fs';
import { sign } from 'node:crypto';
import http2 from 'node:http2';
import { fileURLToPath } from 'node:url';
export function payload(job,device,childName){
 const e=job.entity;
 if(job.type==='reminder')return {topic:'house.thezoo.babytrack',pushType:'alert',token:device.pushToken,body:{aps:{alert:{title:e.title,body:childName},sound:'default',category:'BABYTRACK_REMINDER'},recordID:e.id}};
 const ending=e.end!=null;const activityToken=device.activityTokens?.[e.id]??(device.activityID===e.id?device.activityToken:null);const hasActivity=!!activityToken;
 if(ending&&!hasActivity)return null;
 return {topic:'house.thezoo.babytrack.push-type.liveactivity',pushType:'liveactivity',token:hasActivity?activityToken:device.startToken,body:{aps:{timestamp:Math.floor(Date.now()/1000),event:ending?'end':hasActivity?'update':'start','content-state':{startedAt:e.at,ended:ending},...(ending?{'dismissal-date':Math.floor(Date.now()/1000)}:hasActivity?{}:{'attributes-type':'SleepAttributes',attributes:{sessionID:e.id,childID:e.childID,childName},alert:{title:childName+' is sleeping',body:'Sleep timer started'}})}}};
}
let jwt,issued=0;
export function authorization({keyID,teamID,keyPath},now=Date.now()/1000){
 if(jwt&&now-issued<3000)return jwt;
 const header=Buffer.from(JSON.stringify({alg:'ES256',kid:keyID})).toString('base64url');const body=Buffer.from(JSON.stringify({iss:teamID,iat:Math.floor(now)})).toString('base64url');
 jwt=header+'.'+body+'.'+sign('sha256',Buffer.from(header+'.'+body),{key:readFileSync(keyPath),dsaEncoding:'ieee-p1363'}).toString('base64url');issued=now;return jwt;
}
export async function deliver(message,device,credentials){
 if(!message?.token)return {status:204};
 const host=device.environment==='production'?'https://api.push.apple.com':'https://api.sandbox.push.apple.com';
 const client=http2.connect(host);
 return await new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>{client.destroy();reject(new Error('APNs request timed out'));},10000);
  client.on('error',error=>{clearTimeout(timer);client.destroy();reject(error);});
  const req=client.request({':method':'POST',':path':'/3/device/'+message.token,authorization:'bearer '+authorization(credentials),'apns-topic':message.topic,'apns-push-type':message.pushType,'apns-priority':'10','apns-expiration':String(Math.floor(Date.now()/1000+3600))});
  let status;let body='';req.on('response',headers=>{status=headers[':status'];});req.on('data',chunk=>{body+=chunk;});req.on('end',()=>{clearTimeout(timer);client.close();resolve({status,body});});req.on('error',error=>{clearTimeout(timer);client.destroy();reject(error);});req.end(JSON.stringify(message.body));
 });
}
export async function tick(store,credentials,sender=deliver,now=Date.now()/1000){
 if(!credentials.keyID||!credentials.keyPath||!credentials.teamID)return {configured:false};
 const jobs=store.jobsDue(now);
 for(const row of jobs){
  const job=JSON.parse(row.body);const current=store.list(job.family).find(e=>e.id===job.entity.id);
  if(!current||current.deleted||current.version!==job.entity.version||(job.type==='reminder'&&current.fields.done==='true')){store.removeJob(row.id);continue;}
  const child=store.list(job.family).find(e=>e.id===job.entity.childID);let retry=false;
  const recipients=store.deliveryRecipients(job.family,job.entity.recipientUserID);
  for(const recipient of recipients){const device=JSON.parse(recipient.body);if(!device.enabled||store.delivered(row.id,recipient.user,recipient.id))continue;
   const message=payload(job,device,child?.title??'Baby');
   if(!message?.token){if(job.type==='sleep'&&job.entity.end!=null&&device.startedSessions?.includes(job.entity.id)&&row.attempts<8)retry=true;continue;}
   try{const result=await sender(message,device,credentials);let reason;try{reason=JSON.parse(result.body??'{}').reason;}catch{}
   if([200,204].includes(result.status)){
    store.markDelivered(row.id,recipient.user,recipient.id);
    if(message.body.aps.event==='start'){device.startedSessions=Array.from(new Set([...(device.startedSessions??[]),job.entity.id])).slice(-32);store.saveDevice(recipient.user,recipient.id,device);}
   }
   else if([400,410].includes(result.status)&&['BadDeviceToken','Unregistered','DeviceTokenNotForTopic'].includes(reason)){
    const field=message.pushType==='alert'?'pushToken':message.token===device.startToken?'startToken':'activityToken';delete device[field];if(device.activityTokens)delete device.activityTokens[job.entity.id];store.saveDevice(recipient.user,recipient.id,device);
    store.markDelivered(row.id,recipient.user,recipient.id);
   }else if(result.status>=500||result.status===429)retry=true;
   else store.markDelivered(row.id,recipient.user,recipient.id);
   }catch{retry=true;}
  }
  if(retry&&row.attempts<8){store.retryJob(row.id,now+Math.min(86400,30*2**Math.min(row.attempts,12)));}
  else{
   store.removeJob(row.id);

   if(job.type==='reminder'){const next=nextRepeat(job.entity,now);if(next!=null)store.enqueue(job,next);}
  }
 }
 return {configured:true,processed:jobs.length};
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const store=new Store(process.env.DATABASE_PATH??'./data/babytrack.sqlite');const credentials={keyID:process.env.APNS_KEY_ID,keyPath:process.env.APNS_KEY_PATH,teamID:process.env.APNS_TEAM_ID};
 if(!credentials.keyPath)console.log('APNs credentials missing; queued delivery is paused.');
 let running=false;const timer=setInterval(async()=>{if(running)return;running=true;try{await tick(store,credentials);}catch(error){console.error(error.message);}finally{running=false;}},5000);
 process.on('SIGTERM',()=>{clearInterval(timer);store.close();process.exit(0);});
}
