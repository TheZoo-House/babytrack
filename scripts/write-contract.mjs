import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';

export function writeContract(name,value,{testOnly=false}={}){
 const text=JSON.stringify(value,null,2)+'\n';
 const paths=[`../contracts/${name}.json`,`../app/BabyCore/${testOnly?'Tests/BabyCoreTests':'Sources/BabyCore'}/Resources/${name}.json`];
 for(const path of paths){const url=new URL(path,import.meta.url);if(process.argv.includes('--check'))assert.equal(readFileSync(url,'utf8'),text,`${name} is stale; regenerate its fixture`);else writeFileSync(url,text);}
}
