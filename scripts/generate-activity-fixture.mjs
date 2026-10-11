import {payload} from '../relay/worker.mjs';
import {writeContract} from './write-contract.mjs';
const now=1791589500;Date.now=()=>now*1000;
const entity={id:'synthetic-session',at:now-900,childID:'synthetic-child',end:null};
const start=payload({type:'sleep',entity},{startToken:'synthetic-start'},'Synthetic child').body.aps;
const end=payload({type:'sleep',entity:{...entity,end:now}},{activityTokens:{[entity.id]:'synthetic-activity'}},'Synthetic child').body.aps;
writeContract('activity-payload',{start,end},{testOnly:true});
