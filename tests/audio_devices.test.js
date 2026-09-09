const test = require('node:test');
const assert = require('node:assert/strict');
const {parseInputs} = require('../AudioDevices.js');
test('filters output monitors, preserves microphone labels, removes duplicates', () => {
  assert.deepEqual(parseInputs(JSON.stringify([
    {name: 'onboard', description: 'Onboard microphone', monitor_source: ''},
    {name: 'usb', description: 'USB headset', monitor_of_sink: 4294967295},
    {name: 'usb'},
    {name: 'speaker.monitor'},
    {name: 'monitor-a', monitor_source: 'speaker'},
    {name: 'monitor-b', monitor_of_sink: 0},
    {name: 'monitor-c', properties: {'device.class': 'monitor'}},
    {name: 'monitor-d', properties: {'media.class': 'Audio/Sink'}},
    {name: 'bad|default_output'}, {name: 'bad;option'}, null
  ])), [{name: 'onboard', label: 'Onboard microphone'}, {name: 'usb', label: 'USB headset'}]);
});
test('handles no devices and rejects malformed responses', () => {
  assert.deepEqual(parseInputs('[]'), []);
  assert.throws(() => parseInputs('{}'));
  assert.throws(() => parseInputs('not json'));
});
