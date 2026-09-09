// pactl includes speaker-monitor sources; only offer recording inputs.
function parseInputs(text) {
  var sources = JSON.parse(text)
  if (!Array.isArray(sources)) throw new Error("Invalid audio device list")
  var inputs = []
  var seen = Object.create(null)
  for (var i = 0; i < sources.length; i++) {
    var source = sources[i]
    if (!source || typeof source.name !== "string") continue
    var name = source.name
    var props = source.properties || {}
    if (source.monitor_source || /\.monitor$/.test(name)
        || props["device.class"] === "monitor" || props["media.class"] === "Audio/Sink") continue
    if (source.monitor_of_sink !== undefined && source.monitor_of_sink !== null
        && source.monitor_of_sink !== 4294967295 && source.monitor_of_sink !== "4294967295"
        && source.monitor_of_sink !== -1 && source.monitor_of_sink !== "n/a") continue
    // These characters have meaning inside the recorder's audio-source syntax.
    if (!name || name.length > 512 || /[|;\x00-\x1f\x7f]/.test(name) || seen[name]) continue
    seen[name] = true
    var label = typeof source.description === "string" && source.description ? source.description : name
    inputs.push({name: name, label: label.substring(0, 256)})
  }
  return inputs
}

if (typeof module !== "undefined") module.exports = {parseInputs: parseInputs}
