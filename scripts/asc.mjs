#!/usr/bin/env node
// Credentials come from the caller's environment, never from tracked files.
import { readFileSync } from 'node:fs';
import { sign } from 'node:crypto';
const env=process.env;
if(!env.APP_STORE_CONNECT_KEY_PATH||!env.APP_STORE_CONNECT_KEY_ID||!env.APP_STORE_CONNECT_ISSUER_ID)throw new Error('App Store Connect credentials are missing');
const header=Buffer.from(JSON.stringify({alg:'ES256',kid:env.APP_STORE_CONNECT_KEY_ID,typ:'JWT'})).toString('base64url');
const claims=Buffer.from(JSON.stringify({iss:env.APP_STORE_CONNECT_ISSUER_ID,iat:Math.floor(Date.now()/1000)-10,exp:Math.floor(Date.now()/1000)+600,aud:'appstoreconnect-v1'})).toString('base64url');
const unsigned=header+'.'+claims;
const jwt=unsigned+'.'+sign('sha256',Buffer.from(unsigned),{key:readFileSync(env.APP_STORE_CONNECT_KEY_PATH),dsaEncoding:'ieee-p1363'}).toString('base64url');
const path=process.argv[2]??'/v1/bundleIds?filter[identifier]=house.thezoo.babytrack';
const options={headers:{authorization:'Bearer '+jwt,'content-type':'application/json'},signal:AbortSignal.timeout(15000)};
if(process.argv[3]){options.method='POST';options.body=readFileSync(process.argv[3],'utf8');}
const response=await fetch('https://api.appstoreconnect.apple.com'+path,options);
console.log('App Store Connect HTTP '+response.status);
const body=await response.json();if(response.ok)console.log(JSON.stringify(body));else console.log(JSON.stringify(body.errors??body));
if(!response.ok)process.exitCode=1;
