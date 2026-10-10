import {writeFileSync} from 'node:fs';
import {summary} from '../server/domain.mjs';
const record=(id,type,at,fields={},end=null,childID='synthetic-child')=>({id,type,childID,title:type,at:Date.parse(at)/1000,end:end?Date.parse(end)/1000:null,fields,version:1,updatedAt:0,deleted:false,actor:'Synthetic',detail:''});
const cases=[
 {name:'spring DST and unknown bottle',timeZone:'America/New_York',now:Date.parse('2026-03-08T12:00:00-04:00')/1000,entities:[record('sleep','sleep','2026-03-07T23:00:00-05:00',{},'2026-03-08T08:00:00-04:00'),record('bottle','feeding','2026-03-08T09:00:00-04:00',{amount:'5.5',unit:'oz'}),record('unknown','feeding','2026-03-08T10:00:00-04:00'),record('a-same-time','feeding','2026-03-08T10:00:00-04:00'),record('diaper','diaper','2026-03-08T09:15:00-04:00',{contents:'Both'})]},
 {name:'fall DST and active sleep',timeZone:'America/New_York',now:Date.parse('2026-11-01T03:00:00-05:00')/1000,entities:[record('sleep','sleep','2026-10-31T23:00:00-04:00'),record('bottle','feeding','2026-11-01T01:00:00-05:00',{amount:'50',unit:'mL'}),record('future-sleep','sleep','2026-11-01T05:00:00-05:00',{},'2026-11-01T06:00:00-05:00')]},
 {name:'Tokyo day and child isolation',timeZone:'Asia/Tokyo',now:Date.parse('2026-10-10T10:00:00+09:00')/1000,entities:[record('bottle','feeding','2026-10-09T23:00:00+09:00',{amount:'4',unit:'oz'}),record('reading','reading','2026-10-10T09:00:00+09:00'),record('other','diaper','2026-10-10T09:00:00+09:00',{},null,'other-child'),{...record('deleted','feeding','2026-10-10T09:00:00+09:00',{amount:'10',unit:'oz'}),deleted:true}]}
].map(c=>({...c,childID:'synthetic-child',expected:summary(c.entities,'synthetic-child',c.now,c.timeZone)}));
const data=JSON.stringify(cases,null,2)+'\n';
writeFileSync(new URL('../contracts/summary-cases.json',import.meta.url),data);
writeFileSync(new URL('../app/BabyCore/Sources/BabyCore/Resources/summary-cases.json',import.meta.url),data);
