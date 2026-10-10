#!/usr/bin/env python3
"""The fixed product catalog is the shared form/validation contract."""
import json,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def f(key,label,kind='text',options=None,required=False):
    return dict(key=key,label=label,kind=kind,options=options or [],required=required)
def choice(key,label,options,required=False): return f(key,label,'choice',options,required)
notes=f('notes','Notes','multiline')
catalog=[
 ('feeding','Bottle','waterbottle.fill','amber',[choice('milkType','Milk',['Formula','Breast milk','Mixed']),f('amount','Amount','number',required=True),choice('unit','Unit',['oz','mL'],True),f('brand','Formula brand','formula'),notes]),
 ('diaper','Diaper','drop.fill','mint',[choice('contents','Contents',['Wet','Dirty','Both','Dry'],True),f('detail','Detail'),choice('color','Color',['Yellow','Brown','Green','Black','Red','White','Gray']),choice('consistency','Consistency',['Seedy','Soft','Pasty','Loose','Watery','Hard','Mushy','Runny','Mucous','Solid','Pebbles']),f('blowout','Blowout','toggle'),f('rash','Diaper rash','toggle'),notes]),
 ('sleep','Sleep','moon.zzz.fill','indigo',[choice('category','Type',['Nap','Night'],True),notes]),
 ('reading','Reading','book.fill','rose',[f('itemID','Book','book',required=True),f('minutes','Minutes','number'),notes]),
 ('growth','Measurement','ruler.fill','mint',[choice('measure','Measurement',['Weight','Height','Head circumference'],True),f('value','Value','number',required=True),choice('unit','Unit',['lb','oz','kg','in','cm'],True),notes]),
 ('medication','Medication','pills.fill','rose',[f('dose','Dose',required=True),f('unit','Dose unit',required=True),f('route','Route'),notes]),
 ('temperature','Temperature','thermometer.medium','amber',[f('value','Temperature','number',required=True),choice('unit','Unit',['°F','°C'],True),choice('method','Method',['Rectal','Armpit','Forehead','Ear','Oral']),notes]),
 ('illness','Illness','cross.case.fill','rose',[f('symptoms','Symptoms','multiline'),notes]),
 ('vaccine','Vaccine','syringe.fill','mint',[f('dose','Dose number'),f('provider','Provider'),f('lot','Lot number'),notes]),
 ('milestone','Milestone','sparkles','amber',[notes]),
 ('appointment','Appointment','calendar','indigo',[f('provider','Provider'),f('place','Place'),notes]),
 ('note','Note','note.text','rose',[notes]),
 ('book','Book','books.vertical.fill','rose',[f('isbn','ISBN','barcode'),f('author','Author'),f('giftGiver','Gift giver'),f('locationID','Location','location'),choice('status','Status',['Owned','Lent','Outgrown','Donated']),f('quantity','Quantity','number'),notes]),
 ('toy','Toy','teddybear.fill','amber',[f('brand','Brand'),f('minAge','Minimum age (months)','number'),f('maxAge','Maximum age (months)','number'),f('locationID','Location','location'),choice('status','Status',['Owned','Lent','Outgrown','Donated']),f('quantity','Quantity','number'),notes]),
 ('clothing','Clothing','tshirt.fill','mint',[f('size','Size'),f('brand','Brand'),f('locationID','Location','location'),choice('status','Status',['Owned','Lent','Outgrown','Donated']),f('quantity','Quantity','number'),notes]),
 ('location','Location','mappin.and.ellipse','indigo',[f('parentID','Inside','location'),notes]),
 ('child','Child','face.smiling.fill','amber',[]),
 ('reminder','Reminder','bell.fill','neutral',[choice('trigger','When',['At time','After last log']),choice('recipients','Notify',['All caregivers','Only me']),f('afterHours','After (hours)','number'),f('anchorTitle','Medication'),f('done','Done','toggle'),choice('kind','For',['feeding','medication','vaccine','appointment','other'],True),f('repeatHours','Repeat interval (hours)','number'),notes]),
 ('formula','Formula','waterbottle.fill','amber',[])
]
inventory={'book','toy','clothing','location','formula'}
no_title={'feeding','diaper','sleep','reading','growth','temperature'}
types=[]
for ident,title,symbol,color,fields in catalog:
    if ident not in {'feeding','diaper','sleep','reading'}: color='neutral'
    spec=dict(id=ident,title=title,symbol=symbol,color=color,fields=fields,scope='inventory' if ident in inventory else 'profile' if ident=='child' else 'scheduled' if ident=='reminder' else 'care',titleRequired=ident not in no_title,canSchedule=ident in {'appointment','reminder'})
    if ident=='growth': spec['unitsByMeasure']={'Weight':['lb','oz','kg'],'Height':['in','cm'],'Head circumference':['in','cm']}
    for field in fields:
        if ident=='diaper' and field['key'] in {'color','consistency'}: field['multiple']=True
        labels={'Mucous':'Mucousy'} if field['key']=='consistency' else {'Both':'Wet, Dirty'} if field['key']=='contents' else {'Head circumference':'Head size'} if field['key']=='measure' else {}
        if ident=='reminder' and field['key']=='kind': labels={i:t for i,t,_,_,_ in catalog};labels['other']='Other'
        field['labels']=labels
    types.append(spec)
value={'version':2,'limits':{'csvBytes':7000000,'requestBytes':8000000},'formulaBrands':['Enfamil','Similac','Kendamil','Bobbie','ByHeart',"Earth’s Best",'Kirkland Signature','Nara Organics'], 'types':types}
text=json.dumps(value,indent=2)+'\n'
for path in [root/'contracts/catalog.json',root/'app/BabyCore/Sources/BabyCore/Resources/catalog.json']:
    if '--check' in sys.argv:
        assert path.read_text()==text, f'{path} is stale; regenerate the catalog'
    else: path.write_text(text)
