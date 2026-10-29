import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {PerformanceStore} from '../src/main/performance';
import {defaultConfiguration,normalizeConfiguration} from '../src/core/configuration';

test('new Windows installations keep continuous display and face expansion enabled',async()=>{
    const folder=await mkdtemp(path.join(os.tmpdir(),'tcube-performance-default-'));
    try {
        const store=new PerformanceStore(path.join(folder,'performance.json'));
        assert.deepEqual(await store.load(),{idlePowerSaving:false});
        assert.equal(defaultConfiguration().expandsFacesOnClick,true);
        assert.equal(normalizeConfiguration({...defaultConfiguration(),expandsFacesOnClick:undefined}).expandsFacesOnClick,true);
    } finally {await rm(folder,{recursive:true,force:true});}
});
test('an explicit power-saving or direct-launch choice survives loading',async()=>{
    const folder=await mkdtemp(path.join(os.tmpdir(),'tcube-performance-explicit-'));
    try {
        const file=path.join(folder,'performance.json');
        await new PerformanceStore(file).save(true);
        assert.equal((await new PerformanceStore(file).load()).idlePowerSaving,true);
        assert.equal(normalizeConfiguration({...defaultConfiguration(),expandsFacesOnClick:false}).expandsFacesOnClick,false);
    } finally {await rm(folder,{recursive:true,force:true});}
});
