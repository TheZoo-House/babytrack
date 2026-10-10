import { readFileSync } from 'node:fs';
import {writeContract} from './write-contract.mjs';
import { seedEntities,decorate,summary,feedingPreferences } from '../server/domain.mjs';
import {planNara} from '../server/nara.mjs';
// A fixed synthetic clock makes the fixture independent of live data and accounts.
const now=1791589500;Date.now=()=>now*1000;
const records=seedEntities(now);
const snapshot={version:1,familyID:'sample-family',serverTime:now,entities:records.map(e=>decorate(e,records)).sort((a,b)=>b.at-a.at),summaries:[summary(records,'sample-child',now)],...feedingPreferences(records),members:[{id:'sample-user',name:'Alex'}],user:{id:'sample-user',name:'Alex',preview:true}};
writeContract('sample',snapshot);

const imported=planNara(readFileSync(new URL('../contracts/nara-sample.csv',import.meta.url),'utf8'),{familyID:'synthetic-import-family'}).records;
const importSnapshot={...snapshot,familyID:'synthetic-import-family',entities:imported,summaries:imported.filter(e=>e.type==='child').map(e=>summary(imported,e.id,now)),...feedingPreferences(imported)};
writeContract('nara-import-sample',importSnapshot,{testOnly:true});
