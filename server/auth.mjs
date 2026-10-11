import { createPublicKey, verify } from 'node:crypto';
import { fail } from './domain.mjs';
import { hash } from './store.mjs';
let cachedKeys;let expires=0;let refreshing;
async function refreshKeys(fetcher){
 if(!refreshing)refreshing=(async()=>{const res=await fetcher('https://appleid.apple.com/auth/keys',{signal:AbortSignal.timeout(10000)});if(!res.ok)fail('Apple sign-in is unavailable',503);const keys=(await res.json()).keys;if(!Array.isArray(keys))fail('Apple sign-in is unavailable',503);cachedKeys=keys;expires=Date.now()+3600000;})().finally(()=>{refreshing=undefined;});
 await refreshing;
}
export async function verifyApple(token,nonce,audience,fetcher=fetch){
 if(typeof token!=='string'||token.length>12000)fail('Invalid Apple credential',401);
 try{
  const parts=token.split('.');if(parts.length!==3)fail('Invalid Apple credential',401);
  const header=JSON.parse(Buffer.from(parts[0],'base64url'));const claims=JSON.parse(Buffer.from(parts[1],'base64url'));
  if(header.alg!=='RS256'||claims.iss!=='https://appleid.apple.com'||claims.aud!==audience||typeof claims.sub!=='string'||!claims.sub||!Number.isFinite(claims.exp)||!Number.isFinite(claims.iat)||claims.exp<Date.now()/1000||claims.iat>Date.now()/1000+60||claims.nonce!==hash(nonce))fail('Apple credential could not be verified',401);
  if(!cachedKeys||Date.now()>expires)await refreshKeys(fetcher);
  let key=cachedKeys.find(k=>k.kid===header.kid&&k.kty==='RSA');
  if(!key){await refreshKeys(fetcher);key=cachedKeys.find(k=>k.kid===header.kid&&k.kty==='RSA');}
  if(!key||!verify('RSA-SHA256',Buffer.from(parts[0]+'.'+parts[1]),createPublicKey({key,format:'jwk'}),Buffer.from(parts[2],'base64url')))fail('Apple credential signature is invalid',401);
  return claims.sub;
 }catch(e){if(e.status)throw e;fail('Apple credential could not be verified',401);}
}
