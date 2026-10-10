import http from 'node:http';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Store,hash } from './store.mjs';
import { fail,catalog } from './domain.mjs';
import { verifyApple } from './auth.mjs';
export function createServer(store,{preview=false,audience='house.thezoo.babytrack',verify=verifyApple}={}){
 const limits=new Map();
 return http.createServer(async(req,res)=>{
  const json=(status,body)=>{res.writeHead(status,{'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff'});res.end(JSON.stringify(body));};
  try{
   const url=new URL(req.url,'http://localhost');const method=req.method;
   const key=req.socket.remoteAddress;const now=Date.now();const rate=limits.get(key)??{count:0,reset:now+60000};if(now>rate.reset){rate.count=0;rate.reset=now+60000;}rate.count++;limits.set(key,rate);if(limits.size>10000)for(const [k,v] of limits)if(v.reset<now)limits.delete(k);if(rate.count>180)fail('Too many requests. Try again shortly.',429);
   if(method==='GET'&&url.pathname==='/health')return json(200,{ok:true,contractVersion:1,appleConfigured:!!audience,previewEnabled:preview});
   if(method==='GET'&&url.pathname==='/v1/catalog')return json(200,catalog);
   let body={};if(method==='POST'){const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>8000000)fail('Request is too large',413);chunks.push(chunk);}try{body=JSON.parse(Buffer.concat(chunks).toString()||'{}');}catch{fail('Invalid JSON');}}
   if(method==='POST'&&url.pathname==='/v1/auth/challenge'){const nonce=randomBytes(32).toString('base64url');store.db.prepare('DELETE FROM challenges WHERE expires<?').run(Date.now()/1000);store.db.prepare('INSERT INTO challenges VALUES (?,?)').run(hash(nonce),Date.now()/1000+300);return json(200,{nonce});}
   if(method==='POST'&&url.pathname==='/v1/auth/apple'){
    if(typeof body.nonce!=='string'||!store.db.prepare('SELECT 1 FROM challenges WHERE nonce=? AND expires>?').get(hash(body.nonce),Date.now()/1000))fail('Sign-in session expired. Try again.',401);
    const sub=await verify(body.identityToken,body.nonce,audience);
    const login=store.transaction(()=>{if(store.db.prepare('DELETE FROM challenges WHERE nonce=? AND expires>?').run(hash(body.nonce),Date.now()/1000).changes!==1)fail('Sign-in session was already used',401);return store.login(sub,String(body.name??'Caregiver').slice(0,100)||'Caregiver');});
    return json(200,{...login,snapshot:store.snapshot(store.authenticate(login.token),body.timeZone)});
   }
   if(method==='POST'&&url.pathname==='/v1/auth/preview'){if(!preview)fail('Sample mode is disabled',404);return json(200,store.preview());}
   const user=store.authenticate(req.headers.authorization?.replace(/^Bearer /,''));
   if(method==='POST'&&url.pathname==='/v1/auth/logout'){store.db.prepare('DELETE FROM sessions WHERE token=?').run(hash(req.headers.authorization.replace(/^Bearer /,'')));return json(200,{ok:true});}
   if(method==='POST'&&url.pathname==='/v1/caregiver/profile')return json(200,store.updateCaregiver(user,body));
   if(method==='GET'&&url.pathname==='/v1/snapshot')return json(200,store.snapshot(user,url.searchParams.get('timeZone')));
   if(method==='POST'&&url.pathname==='/v1/sync'){
    if(!Array.isArray(body.commands)||body.commands.length>50)fail('Send at most 50 operations');
    const results=body.commands.map(command=>{try{return store.command(user,command);}catch(e){return {id:command?.id??'',status:'rejected',message:e.message};}});
    return json(200,{results,snapshot:store.snapshot(user,body.timeZone)});
   }
   if(method==='POST'&&['/v1/import/nara/preview','/v1/import/nara/commit'].includes(url.pathname))return json(200,store.importNara(user,{...body,commit:url.pathname.endsWith('/commit')}));
   if(method==='POST'&&url.pathname==='/v1/invites')return json(200,store.invite(user));
   if(method==='POST'&&url.pathname==='/v1/invites/join')return json(200,{snapshot:store.snapshot(store.join(user,String(body.code??'')),body.timeZone)});
   if(method==='POST'&&url.pathname==='/v1/devices'){
    if(typeof body.id!=='string'||body.id.length>100||!body.id)fail('Invalid device');
    const tokens=['pushToken','startToken','activityToken'];for(const k of tokens)if(body[k]!=null&&(typeof body[k]!=='string'||!/^([a-f0-9]{2}){16,128}$/.test(body[k])))fail('Invalid push token');
    const data={id:body.id,enabled:!!body.enabled,environment:body.environment==='production'?'production':'sandbox'};
    for(const field of [...tokens,'activityID'])if(body[field]!=null)data[field]=String(body[field]).slice(0,field==='activityID'?80:256);
    const old=store.db.prepare('SELECT body FROM devices WHERE user=? AND id=?').get(user.id,data.id);const merged={...(old?JSON.parse(old.body):{}),...data};
    if(data.activityID&&data.activityToken){merged.activityTokens={...(merged.activityTokens??{}),[data.activityID]:data.activityToken};merged.activityTokens=Object.fromEntries(Object.entries(merged.activityTokens).slice(-32));}
    store.db.prepare('INSERT INTO devices VALUES (?,?,?) ON CONFLICT(user,id) DO UPDATE SET body=excluded.body').run(user.id,data.id,JSON.stringify(merged));return json(200,{ok:true});
   }
   if(method==='GET'&&url.pathname==='/v1/books/lookup'){
    const isbn=(url.searchParams.get('isbn')??'').replace(/[-\s]/g,'');if(!/^(\d{13}|\d{9}[\dXx])$/.test(isbn))fail('Enter a 10 or 13 digit ISBN');
    const response=await fetch(`https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`,{signal:AbortSignal.timeout(10000),headers:{'user-agent':'Babytrack/0.1 (family ISBN lookup)'}});if(!response.ok)fail('Book lookup is unavailable. Enter the book manually.',503);
    const book=(await response.json())['ISBN:'+isbn];if(!book)fail('Book not found. Enter the title manually.',404);
    return json(200,{title:book.title??'',author:(book.authors??[]).map(a=>a.name).join(', '),isbn,imageURL:`https://covers.openlibrary.org/b/isbn/${isbn}-M.jpg`});
   }
   if(method==='GET'&&url.pathname==='/v1/export')return json(200,{...store.snapshot(user),exportedAt:Date.now()/1000});
   if(method==='POST'&&url.pathname==='/v1/account/delete'){
    store.transaction(()=>{store.db.prepare('DELETE FROM sessions WHERE user=?').run(user.id);store.db.prepare('DELETE FROM devices WHERE user=?').run(user.id);store.db.prepare('DELETE FROM members WHERE user=?').run(user.id);store.db.prepare('DELETE FROM users WHERE id=?').run(user.id);if(!store.db.prepare('SELECT 1 FROM members WHERE family=?').get(user.family)){for(const table of ['entities','operations','invites'])store.db.prepare(`DELETE FROM ${table} WHERE family=?`).run(user.family);store.db.prepare('DELETE FROM jobs WHERE json_extract(body,\'$.family\')=?').run(user.family);}});return json(200,{ok:true});
   }
   fail('Not found',404);
  }catch(e){json(e.status??500,{error:e.status?e.message:'The server could not complete this request.'});if(!e.status)console.error(e);}
 });
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const path=process.env.DATABASE_PATH??'./data/babytrack.sqlite';mkdirSync(dirname(path),{recursive:true});
 const store=new Store(path);const server=createServer(store,{preview:process.env.PREVIEW_ENABLED==='1',audience:process.env.APPLE_CLIENT_ID??'house.thezoo.babytrack'});
 server.listen(Number(process.env.PORT??8792),process.env.HOST??'127.0.0.1',()=>console.log('Babytrack backend listening on '+server.address().port));
 process.on('SIGTERM',()=>server.close(()=>{store.close();process.exit(0);}));
}
