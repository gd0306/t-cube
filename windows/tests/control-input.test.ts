import assert from 'node:assert/strict';
import test from 'node:test';
import { rawInputInterferes, otherInputHeld } from '../src/native/control-input';

test('raw input catches transient keys, all mouse buttons and both wheel axes without treating motion or Ctrl as interference', () => {
    const packet = Buffer.alloc(48); packet.writeUInt32LE(48,4);
    for (const flags of [1,2,4,8,16,32,64,128,256,512,1024,2048]) {
        packet.writeUInt32LE(0,0); packet.writeUInt16LE(flags,28); assert.equal(rawInputInterferes(packet,24),true);
    }
    packet.writeUInt16LE(0,28); packet.writeInt32LE(99,36); assert.equal(rawInputInterferes(packet,24),false);
    packet.writeUInt32LE(1,0);
    for (const key of [0x11,0xa2,0xa3]) { packet.writeUInt16LE(key,30); assert.equal(rawInputInterferes(packet,24),false); }
    for (const key of [0x10,0x12,0x43,0x5b]) { packet.writeUInt16LE(key,30); assert.equal(rawInputInterferes(packet,24),true); }
    assert.equal(rawInputInterferes(Buffer.alloc(2),24),false);
});
test('a key already held before Ctrl disqualifies a hold, excluding left and right control aliases', () => {
    for (const key of [1,2,4,5,6,0x10,0x12,0x43,0x5b]) assert.equal(otherInputHeld(value => value===key?-32768:0),true);
    assert.equal(otherInputHeld(value => [0x11,0xa2,0xa3].includes(value)?-32768:0),false);
});

test('physical Ctrl release is observed even when release/repress occur between polls', async () => {
    const {rawControlReleased}=await import('../src/native/control-input');
    const packet=Buffer.alloc(48);packet.writeUInt32LE(1,0);packet.writeUInt16LE(0xa2,30);
    assert.equal(rawControlReleased(packet,24),false);
    packet.writeUInt16LE(1,26);assert.equal(rawControlReleased(packet,24),true);
    packet.writeUInt16LE(0x43,30);assert.equal(rawControlReleased(packet,24),false);
});

test('raw Ctrl-down starts timing between polls, repeat/second Ctrl do not restart it and last release rearms', async () => {
    const { RawControlState } = await import('../src/native/control-input');
    const { ControlHoldGesture } = await import('../src/core/control-hold');
    const raw = new RawControlState(false, false), gesture = new ControlHoldGesture();
    gesture.update({available:true,controlHeld:false,interrupted:false},0);
    const packet=Buffer.alloc(48);packet.writeUInt32LE(1,0);packet.writeUInt16LE(0xa2,30);
    assert.equal(raw.update(packet,24),'pressed');
    gesture.update({available:true,controlHeld:true,interrupted:false},37);
    assert.equal(raw.update(packet,24),null,'Repeated make must not restart the hold');
    packet.writeUInt16LE(0xa3,30);assert.equal(raw.update(packet,24),null);
    for(let now=80;now<2037;now+=80)assert.equal(gesture.update({available:true,controlHeld:true,interrupted:false},now),false);
    assert.equal(gesture.update({available:true,controlHeld:true,interrupted:false},2037),true);
    packet.writeUInt16LE(1,26);assert.equal(raw.update(packet,24),null,'One Ctrl still held');
    packet.writeUInt16LE(0xa2,30);assert.equal(raw.update(packet,24),'released');
});

test('raw state baselines held Ctrl without starting a gesture after startup or resume', async () => {
    const { RawControlState } = await import('../src/native/control-input');
    const raw=new RawControlState(true,false),packet=Buffer.alloc(48);
    packet.writeUInt32LE(1,0);packet.writeUInt16LE(0xa2,30);
    assert.equal(raw.update(packet,24),null,'Startup autorepeat cannot start a new press');
    packet.writeUInt16LE(1,26);assert.equal(raw.update(packet,24),'released');
    packet.writeUInt16LE(0,26);assert.equal(raw.update(packet,24),'pressed');
    raw.baseline(true,false);assert.equal(raw.update(packet,24),null,'Resume must baseline existing physical state');
});
