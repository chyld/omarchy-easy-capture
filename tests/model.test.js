const test = require('node:test');
const assert = require('node:assert/strict');
const model = require('../CaptureModel.js');
test('bounded normalized device messages', () => {
  const data = {event:'microphones', items:[{name:'usb',label:'Headset'}]};
  assert.deepEqual(model.event(JSON.stringify(data)),data);
  for (const bad of [
    {event:'microphones',items:[{name:'usb',label:'<img src="file:/x">'}]},
    {event:'microphones',items:Array(33).fill({name:'usb',label:'USB'})},
    {event:'monitors',items:[{name:'DP-1',width:'1920',height:1080}]},
    {event:'phase',phase:'execute'}, {event:'error',message:'bad\ntext'}
  ]) assert.throws(() => model.event(JSON.stringify(bad)));
  assert.throws(() => model.event('['.repeat(9)+']'.repeat(9)));
  assert.throws(() => model.event('x'.repeat(32769)));
});
test('event names and benign phase messages', () => {
  assert.equal(model.event('{"event":"phase","phase":"recording"}').phase,'recording');
  assert.equal(model.event('{"event":"cancelled"}').event,'cancelled');
  assert.equal(model.name('bad|input'),false);
  assert.equal(model.name('-option'),false);
});
