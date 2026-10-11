import {catalog,decorate} from '../server/domain.mjs';
import {writeContract} from './write-contract.mjs';
const now=1791589500;
const record=(id,type,fields={},extra={})=>({id,type,title:type,childID:'synthetic-child',at:now-300,end:null,fields,version:1,updatedAt:now,deleted:false,actor:'Synthetic',detail:'',...extra});
const references=[record('book-reference','book',{author:'Synthetic author'},{title:'Synthetic story'}),record('parent-location','location',{}, {title:'Nursery'}),record('child-location','location',{parentID:'parent-location'},{title:'Shelf'})];
const examples={
 feeding:{amount:'5.5',unit:'oz',brand:'Similac',milkType:'Formula'},
 diaper:{contents:'Both',color:'Brown Yellow',consistency:'Mucous Mushy',detail:'Blowout',rash:'true'},
 sleep:{category:'Nap'},reading:{itemID:'book-reference',minutes:'8'},
 growth:{measure:'Head circumference',value:'40.5',unit:'cm'},
 temperature:{value:'36.5',unit:'°C',method:'Armpit'},medication:{dose:'2.5',unit:'mL',route:'Oral'},
 book:{author:'Synthetic author',locationID:'child-location',status:'Owned'},
 toy:{brand:'Synthetic',minAge:'0',maxAge:'6',locationID:'child-location',status:'Owned'},
 clothing:{size:'3 months',brand:'Synthetic',locationID:'child-location',status:'Owned'},
 location:{parentID:'child-location'},vaccine:{provider:'Synthetic clinic'},illness:{symptoms:'Synthetic symptom'},note:{notes:'Quoted "note"\nUnicode 😀'}
};
const cases=catalog.types.map(type=>record('case-'+type.id,type.id,examples[type.id]??{notes:'Synthetic note'},type.id==='sleep'?{end:now+300}:type.id==='child'?{at:now-86400*91}:{}));
cases.push(record('active','sleep',{category:'Night'}),record('unknown-medication','medication',{}),record('unknown-bottle','feeding',{}),record('breast-bottle','feeding',{amount:'50',unit:'mL',milkType:'Breast milk',brand:'Hidden brand'}));
const fixtures=cases.map(entity=>({name:entity.id,entity,records:references,now,expected:decorate(entity,[entity,...references],now).detail}));
writeContract('detail-cases',fixtures,{testOnly:true});
