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
test('share and config events are bounded and validated', () => {
  assert.equal(model.event('{"event":"shared","url":"https://zipline.example/r/abc"}').url,'https://zipline.example/r/abc');
  assert.equal(model.event('{"event":"share_error","message":"Share upload failed"}').message,'Share upload failed');
  assert.equal(model.event('{"event":"config","server":"https://zipline.example?a=1&b=2","token":"abc"}').server,'https://zipline.example?a=1&b=2');
  assert.equal(model.event('{"event":"config_saved"}').event,'config_saved');
  for (const bad of [
    {event:'shared',url:'http://zipline.example/r/abc'},
    {event:'shared',url:'https://x/'.padEnd(2050,'a')},
    {event:'shared',url:'https://x/\u0000'},
    {event:'share_error',message:'bad\ntext'},
    {event:'config',server:'https://x',token:'bad\u0000'}
  ]) assert.throws(() => model.event(JSON.stringify(bad)));
});
