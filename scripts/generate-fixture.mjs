import { readFileSync,writeFileSync } from 'node:fs';
import { seedEntities,decorate,summary,feedingPreferences } from '../server/domain.mjs';
import {planNara} from '../server/nara.mjs';
// A fixed synthetic clock makes the fixture independent of live data and accounts.
const now=1791589500;Date.now=()=>now*1000;
const records=seedEntities(now);
const snapshot={version:1,familyID:'sample-family',serverTime:now,entities:records.map(e=>decorate(e,records)).sort((a,b)=>b.at-a.at),summaries:[summary(records,'sample-child',now)],...feedingPreferences(records),members:[{id:'sample-user',name:'Alex'}],user:{id:'sample-user',name:'Alex',preview:true}};
for(const path of ['../contracts/sample.json','../app/BabyCore/Sources/BabyCore/Resources/sample.json'])writeFileSync(new URL(path,import.meta.url),JSON.stringify(snapshot,null,2)+'\n');

const imported=planNara(readFileSync(new URL('../contracts/nara-sample.csv',import.meta.url),'utf8'),{familyID:'synthetic-import-family'}).records;
const importSnapshot={...snapshot,familyID:'synthetic-import-family',entities:imported,summaries:imported.filter(e=>e.type==='child').map(e=>summary(imported,e.id,now)),...feedingPreferences(imported)};
for(const path of ['../contracts/nara-import-sample.json','../app/BabyCore/Sources/BabyCore/Resources/nara-import-sample.json'])writeFileSync(new URL(path,import.meta.url),JSON.stringify(importSnapshot,null,2)+'\n');
