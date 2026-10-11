import http from 'node:http';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { isIP } from 'node:net';
import { fileURLToPath } from 'node:url';
import { Store } from './store.mjs';
import { fail,catalog } from './domain.mjs';
import { verifyApple } from './auth.mjs';
export function createServer(store,{preview=false,audience='house.thezoo.babytrack',verify=verifyApple,rateLimit=180,previewLimit=12}={}){
 const limits=new Map();
 function limited(key,maximum,window=60000){const now=Date.now();const rate=limits.get(key)??{count:0,reset:now+window};if(now>=rate.reset){rate.count=0;rate.reset=now+window;}rate.count++;limits.set(key,rate);if(limits.size>10000)for(const [k,v] of limits)if(v.reset<now)limits.delete(k);if(rate.count>maximum)fail('Too many requests. Try again shortly.',429);}
 return http.createServer(async(req,res)=>{
  const json=(status,body)=>{res.writeHead(status,{'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff'});res.end(JSON.stringify(body));};
  try{
   const url=new URL(req.url,'http://localhost');const method=req.method;
   const token=req.headers.authorization?.replace(/^Bearer /,'');
   const publicRoute=['/health','/v1/catalog','/v1/auth/challenge','/v1/auth/apple','/v1/auth/preview'].includes(url.pathname);
   let user,authenticationError;if(!publicRoute){try{user=store.authenticate(token);}catch(error){authenticationError=error;}}
   const remote=req.socket.remoteAddress??'unknown';const forwarded=String(req.headers['x-forwarded-for']??'').split(',').at(-1).trim();
   const address=['127.0.0.1','::1','::ffff:127.0.0.1'].includes(remote)&&isIP(forwarded)?forwarded:remote;
   limited(user?'user:'+user.id:'ip:'+address,rateLimit);
   if(authenticationError)throw authenticationError;
   if(method==='GET'&&url.pathname==='/health')return json(200,{ok:true,contractVersion:1,appleConfigured:!!audience,previewEnabled:preview});
   if(method==='GET'&&url.pathname==='/v1/catalog')return json(200,catalog);
   let body={};if(method==='POST'){const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>catalog.limits.requestBytes)fail('Request is too large',413);chunks.push(chunk);}try{body=JSON.parse(Buffer.concat(chunks).toString()||'{}');}catch{fail('Invalid JSON');}if(!body||typeof body!=='object'||Array.isArray(body))fail('Send a JSON object');}
   // Membership or the session can change while a request is uploading.
   if(user&&method==='POST')user=store.authenticate(token);
   if(method==='POST'&&url.pathname==='/v1/auth/challenge')return json(200,{nonce:store.issueChallenge()});
   if(method==='POST'&&url.pathname==='/v1/auth/apple'){
    if(!store.validChallenge(body.nonce))fail('Sign-in session expired. Try again.',401);
    const sub=await verify(body.identityToken,body.nonce,audience);
    const login=store.consumeChallenge(body.nonce,sub,String(body.name??'Caregiver').slice(0,100)||'Caregiver');
    return json(200,{...login,snapshot:store.snapshot(store.authenticate(login.token),body.timeZone)});
   }
   if(method==='POST'&&url.pathname==='/v1/auth/preview'){if(!preview)fail('Sample mode is disabled',404);limited('preview:'+address,previewLimit,3600000);store.expirePreviews();return json(200,store.preview());}
   if(method==='POST'&&url.pathname==='/v1/auth/logout'){store.logout(token);return json(200,{ok:true});}
   if(method==='POST'&&url.pathname==='/v1/caregiver/profile')return json(200,store.updateCaregiver(user,body));
   if(method==='GET'&&url.pathname==='/v1/snapshot')return json(200,store.snapshot(user,url.searchParams.get('timeZone')));
   if(method==='POST'&&url.pathname==='/v1/sync')return json(200,store.sync(user,body.commands,body.timeZone,body.familyID));
   if(method==='GET'&&url.pathname.startsWith('/v1/import-source/'))return json(200,store.source(user,decodeURIComponent(url.pathname.slice('/v1/import-source/'.length))));
   if(method==='POST'&&['/v1/import/nara/preview','/v1/import/nara/commit'].includes(url.pathname))return json(200,store.importNara(user,{...body,commit:url.pathname.endsWith('/commit')}));
   if(method==='POST'&&url.pathname==='/v1/invites')return json(200,store.invite(user));
   if(method==='POST'&&url.pathname==='/v1/invites/join')return json(200,{snapshot:store.snapshot(store.join(user,String(body.code??'')),body.timeZone)});
   if(method==='POST'&&url.pathname==='/v1/devices'){
    store.registerDevice(user,body);return json(200,{ok:true});
   }
   if(method==='GET'&&url.pathname==='/v1/books/lookup'){
    const isbn=(url.searchParams.get('isbn')??'').replace(/[-\s]/g,'');if(!/^(\d{13}|\d{9}[\dXx])$/.test(isbn))fail('Enter a 10 or 13 digit ISBN');
    const response=await fetch(`https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`,{signal:AbortSignal.timeout(10000),headers:{'user-agent':'Babytrack/0.1 (family ISBN lookup)'}});if(!response.ok)fail('Book lookup is unavailable. Enter the book manually.',503);
    const book=(await response.json())['ISBN:'+isbn];if(!book)fail('Book not found. Enter the title manually.',404);
    return json(200,{title:book.title??'',author:(book.authors??[]).map(a=>a.name).join(', '),isbn,imageURL:`https://covers.openlibrary.org/b/isbn/${isbn}-M.jpg`});
   }
   if(method==='GET'&&url.pathname==='/v1/export')return json(200,{...store.snapshot(user,undefined,{includeSource:true}),exportedAt:Date.now()/1000});
   if(method==='POST'&&url.pathname==='/v1/account/delete'){
    store.deleteAccount(user);return json(200,{ok:true});
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
