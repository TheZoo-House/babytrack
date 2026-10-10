import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
export const catalog=JSON.parse(readFileSync(new URL('../contracts/catalog.json',import.meta.url)));
const inventory=new Set(['book','toy','clothing','location','formula']);
export const careTypes=new Set(catalog.types.map(t=>t.id).filter(t=>!inventory.has(t)&&!['child','reminder'].includes(t)));
export function fail(message,status=400){throw Object.assign(new Error(message),{status});}
export function validateEntity(input,{imported=false}={}){
 if(!input||typeof input!=='object')fail('A record is required');
 const spec=catalog.types.find(t=>t.id===input.type);if(!spec)fail('Unknown record type');
 if(typeof input.id!=='string'||!/^[-a-zA-Z0-9]{1,80}$/.test(input.id))fail('Invalid record ID');
 if(typeof input.title!=='string'||input.title.length>240||!input.title.trim())fail('Enter a title');
 if(!Number.isFinite(input.at)||input.at<0||input.at>4102444800)fail('Invalid record date');
 if(input.end!=null&&(!Number.isFinite(input.end)||input.end<input.at))fail('End must follow start');
 if(input.type==='sleep'&&input.end!=null&&input.end-input.at>86400*7)fail('Check the sleep end date');
 const fields=input.fields??{};if(typeof fields!=='object'||Array.isArray(fields))fail('Invalid fields');
 // Older apps may still send offered; preserve existing records during upgrades.
 const allowed=new Set(spec.fields.map(f=>f.key).concat(['photo','imageURL'],input.type==='feeding'?['offered']:[]));
 for(const [key,value] of Object.entries(fields)){
   if(!allowed.has(key)||typeof value!=='string'||value.length>(key==='photo'?1500000:4000))fail(`Invalid ${key}`);
   if(key==='imageURL'&&value&&!/^https:\/\/(covers\.openlibrary\.org|openlibrary\.org)\//.test(value))fail('Invalid cover URL');
 }
 for(const field of spec.fields){const value=fields[field.key];
   if(!imported&&field.required&&!value?.trim())fail(`Enter ${field.label.toLowerCase()}`);
   if(!imported&&value&&field.kind==='choice'&&!field.options.includes(value))fail(`Invalid ${field.label.toLowerCase()}`);
   if(value&&field.kind==='number'&&(!Number.isFinite(Number(value))||Number(value)<0||Number(value)>100000))fail(`Check ${field.label.toLowerCase()}`);
 }
 if(input.type==='feeding'&&fields.amount!=null&&Number(fields.amount)<=0)fail('Amount must be greater than zero');
 if(input.type==='formula'&&input.title.trim().length>80)fail('Formula name must be 80 characters or fewer');
 if(input.type==='growth'&&!imported){
   const units=fields.measure==='Weight'?['lb','oz','kg']:['in','cm'];
   if(!units.includes(fields.unit))fail('Choose a unit for this measurement');
 }
 if(input.type==='reminder'&&fields.repeatHours&&Number(fields.repeatHours)<=0)fail('Repeat interval must be greater than zero');
 return {id:input.id,type:input.type,childID:input.childID??'',title:input.title.trim(),at:input.at,end:input.end??null,fields,version:input.version??0,updatedAt:0,deleted:!!input.deleted,actor:'',detail:''};
}
export function feedingPreferences(entities){
 const active=entities.filter(e=>!e.deleted);
 const names=new Map(catalog.formulaBrands.map(name=>[name.toLocaleLowerCase('en-US'),name]));
 for(const name of active.flatMap(e=>e.type==='formula'?[e.title]:e.type==='feeding'&&e.fields.brand?[e.fields.brand]:[])){
  const trimmed=name.trim();if(trimmed&&!names.has(trimmed.toLocaleLowerCase('en-US')))names.set(trimmed.toLocaleLowerCase('en-US'),trimmed);
 }
 const formulaBrands=[...names.values()];
 const feedingDefaults=active.filter(e=>e.type==='child').map(child=>{
  const last=active.filter(e=>e.type==='feeding'&&e.childID===child.id&&e.fields.brand?.trim()).sort((a,b)=>b.at-a.at||b.updatedAt-a.updatedAt||a.id.localeCompare(b.id))[0];
  return {childID:child.id,formula:last?names.get(last.fields.brand.trim().toLocaleLowerCase('en-US')):null};
 });
 return {formulaBrands,feedingDefaults};
}
export function decorate(entity,entities){
 const f=entity.fields;let detail='';
 const reference=id=>entities.find(e=>e.id===id&&!e.deleted)?.title??'';
 const location=id=>{const names=[];const seen=new Set();while(id&&!seen.has(id)){seen.add(id);const e=entities.find(e=>e.id===id&&!e.deleted&&e.type==='location');if(!e)break;names.unshift(e.title);id=e.fields.parentID;}return names.join(' → ');};
 switch(entity.type){
 case 'feeding':detail=[f.amount?`${f.amount} ${f.unit}`:'Amount not recorded',f.brand].filter(Boolean).join(' · ');break;
 case 'diaper':detail=[f.contents,...(f.contents==='Dirty'||f.contents==='Both'?[f.detail,f.color,f.consistency]:[])].filter(Boolean).join(' · ');break;
 case 'sleep':detail=entity.end!=null?[`${Math.round((entity.end-entity.at)/60)} min`,f.category].filter(Boolean).join(' · '):(f.category||'Sleeping');break;
 case 'reading':detail=[reference(f.itemID),f.minutes?f.minutes+' min':''].filter(Boolean).join(' · ');break;
 case 'growth':detail=`${f.measure} · ${f.value} ${f.unit||"· unit unknown"}`;break;
 case 'temperature':detail=[`${f.value} ${f.unit||"· unit unknown"}`,f.method].filter(Boolean).join(' · ');break;
 case 'medication':detail=[f.dose?`${f.dose} ${f.unit||'· unit unknown'}`:'Dose not recorded',f.route].filter(Boolean).join(' · ');break;
 case 'book':detail=[f.author,location(f.locationID),f.status].filter(Boolean).join(' · ');break;
 case 'toy':detail=[f.brand,f.minAge!=null&&f.minAge!==''?`${f.minAge}${f.maxAge?'–'+f.maxAge:'+'} months`:'',location(f.locationID),f.status].filter(Boolean).join(' · ');break;
 case 'clothing':detail=[f.size,f.brand,location(f.locationID),f.status].filter(Boolean).join(' · ');break;
 case 'location':detail=location(f.parentID);break;
 case 'child':{if(entity.at===0&&entity.imported){detail='Birthday not recorded';break;}const months=Math.max(0,Math.floor((Date.now()/1000-entity.at)/(86400*30.4375)));detail=months?`${months} month${months===1?'':'s'} old`:'Newborn';break;}
 default:detail=f.provider||f.symptoms||f.notes||'';
 }
 return {...entity,detail,scheduled:['appointment','reminder'].includes(entity.type)&&entity.at>Date.now()/1000};
}
export function summary(entities,childID,now=Date.now()/1000,timeZone='America/New_York'){
 let format;try{format=new Intl.DateTimeFormat('en-CA',{timeZone,year:'numeric',month:'2-digit',day:'2-digit'});}catch{format=new Intl.DateTimeFormat('en-CA',{timeZone:'UTC',year:'numeric',month:'2-digit',day:'2-digit'});}
 const date=format.format(new Date(now*1000));const day=entities.filter(e=>e.childID===childID&&careTypes.has(e.type)&&!e.deleted&&format.format(new Date(e.at*1000))===date);
 const feeds=day.filter(e=>e.type==='feeding');
 const ml=feeds.reduce((n,e)=>n+(e.fields.amount&&['oz','mL'].includes(e.fields.unit)?Number(e.fields.amount)*(e.fields.unit==='oz'?29.5735295625:1):0),0);
 let low=now-172800,high=now;
 for(let i=0;i<40;i++){const middle=(low+high)/2;if(format.format(new Date(middle*1000))===date)high=middle;else low=middle;}
 const dayStart=Math.round(high);
 const sleep=entities.filter(e=>e.childID===childID&&e.type==='sleep'&&!e.deleted).reduce((n,e)=>n+Math.max(0,Math.min(e.end??now,now)-Math.max(e.at,dayStart))/60,0);
 const lastID=type=>entities.filter(e=>e.childID===childID&&e.type===type&&!e.deleted).sort((a,b)=>b.at-a.at||a.id.localeCompare(b.id))[0]?.id??null;
 return {childID,feedingCount:feeds.length,feedingML:Math.round(ml),diaperCount:day.filter(e=>e.type==='diaper').length,sleepMinutes:Math.round(sleep),readingCount:day.filter(e=>e.type==='reading').length,day:date,lastFeedingID:lastID('feeding'),lastDiaperID:lastID('diaper'),lastSleepID:lastID('sleep')};
}
export function seedEntities(now=Date.now()/1000){
 const child='sample-child',book='sample-book';
 const e=(id,type,title,at,fields={},childID=child,end=null)=>({id,type,title,at,fields,childID,end,version:1,updatedAt:now,deleted:false,actor:'Alex',detail:''});
 return [e(child,'child','Robin',now-86400*91,{},''),e('sample-location','location','Nursery shelf',now,{},''),
 e(book,'book','Goodnight Moon',now,{isbn:'9780064430173',author:'Margaret Wise Brown',giftGiver:'Grandma',locationID:'sample-location',status:'Owned',quantity:'1',imageURL:'https://covers.openlibrary.org/b/isbn/9780064430173-M.jpg'},''),
 e('sample-book-2','book','The Very Hungry Caterpillar',now,{isbn:'9780399226908',author:'Eric Carle',giftGiver:'Sam',status:'Owned',locationID:'sample-location',imageURL:'https://covers.openlibrary.org/b/isbn/9780399226908-M.jpg'},''),
 e('sample-toy','toy','Little bear',now,{brand:'Jellycat',minAge:'0',status:'Owned',locationID:'sample-location'},''),
 e('sample-clothes','clothing','Striped sleep suit',now,{brand:'Hanna Andersson',size:'3–6 months',status:'Owned',locationID:'sample-location'},''),
 e('sample-feed-1','feeding','Bottle',now-7200,{amount:'4',unit:'oz',brand:'Formula'}),
 e('sample-feed-2','feeding','Bottle',now-21000,{amount:'4',unit:'oz',brand:'Formula'}),
 e('sample-diaper','diaper','Diaper',now-3600,{contents:'Wet'}),
 e('sample-sleep','sleep','Sleep',now-15000,{category:'Nap'},child,now-10500),
 e('sample-read','reading','Reading',now-5000,{itemID:book,minutes:'8'}),
 e('sample-weight','growth','Measurement',now-86400*4,{measure:'Weight',value:'13.2',unit:'lb'}),
 e('sample-height','growth','Measurement',now-86400*4,{measure:'Height',value:'24.1',unit:'in'}),
 e('sample-head','growth','Measurement',now-86400*4,{measure:'Head circumference',value:'16',unit:'in'}),
 e('sample-milestone','milestone','First laugh',now-86400*2,{notes:'During story time.'}),
 e('sample-appointment','appointment','Well-child visit',now+86400*12,{provider:'Pediatrician'}),
 e('sample-vaccine','vaccine','DTaP',now-86400*30,{dose:'1',provider:'Pediatrician'})];
}
