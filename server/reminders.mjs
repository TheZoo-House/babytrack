export function reminderDue(entity,records,now=Date.now()/1000){
 if(entity.deleted||entity.fields.done==='true')return null;
 let due=entity.at;
 if(entity.fields.trigger==='After last log'){
  const title=entity.fields.anchorTitle?.trim().toLocaleLowerCase('en-US');
  const latest=records.filter(e=>!e.deleted&&e.childID===entity.childID&&e.type===entity.fields.kind&&e.at<=now&&(!title||e.title.trim().toLocaleLowerCase('en-US')===title)).sort((a,b)=>b.at-a.at)[0];
  due=(latest?.at??entity.createdAt??now)+Number(entity.fields.afterHours)*3600;
 }
 return Math.max(due,entity.snoozedUntil??0);
}

export function nextRepeat(entity,now){
 const interval=Number(entity.fields.repeatHours)*3600;
 if(!Number.isFinite(interval)||interval<=0||entity.fields.done==='true')return null;
 return entity.at+(Math.floor(Math.max(0,now-entity.at)/interval)+1)*interval;
}
