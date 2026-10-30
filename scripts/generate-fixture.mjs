import { writeFileSync } from 'node:fs';
import { seedEntities,decorate,summary } from '../server/domain.mjs';
// A fixed synthetic clock makes the fixture independent of live data and accounts.
const now=1791589500;Date.now=()=>now*1000;
const records=seedEntities(now);
const snapshot={version:1,familyID:'sample-family',serverTime:now,entities:records.map(e=>decorate(e,records)).sort((a,b)=>b.at-a.at),summaries:[summary(records,'sample-child',now)],members:[{id:'sample-user',name:'Alex'}],user:{id:'sample-user',name:'Alex',preview:true}};
for(const path of ['../contracts/sample.json','../app/BabyCore/Sources/BabyCore/Resources/sample.json'])writeFileSync(new URL(path,import.meta.url),JSON.stringify(snapshot,null,2)+'\n');
