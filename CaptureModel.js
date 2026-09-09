function name(value) {
  return typeof value === "string" && /^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,255}$/.test(value)
}
function text(value, max) {
  return typeof value === "string" && value.length <= max
    && !/[<>&\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/.test(value)
}
function event(raw) {
  if (raw.length > 32768) throw new Error("oversize event")
  var depth = 0, quoted = false, escaped = false
  for (var i = 0; i < raw.length; i++) {
    var c = raw[i]
    if (escaped) escaped = false
    else if (quoted && c === "\\") escaped = true
    else if (c === '"') quoted = !quoted
    else if (!quoted && (c === "[" || c === "{")) {
      if (++depth > 8) throw new Error("event nesting")
    } else if (!quoted && (c === "]" || c === "}")) depth--
  }
  var data = JSON.parse(raw)
  if (!data || typeof data !== "object" || Array.isArray(data) || Object.keys(data).length > 4)
    throw new Error("invalid event")
  if (data.event === "monitors" || data.event === "microphones") {
    var max = data.event === "monitors" ? 16 : 32
    if (!Array.isArray(data.items) || data.items.length > max) throw new Error("item count")
    var seen = Object.create(null)
    for (var j = 0; j < data.items.length; j++) {
      var item = data.items[j]
      if (!item || !name(item.name) || seen[item.name]) throw new Error("invalid device")
      seen[item.name] = true
      if (data.event === "microphones") {
        if (!text(item.label, 128) || Object.keys(item).length !== 2) throw new Error("invalid label")
      } else if (!Number.isInteger(item.width) || !Number.isInteger(item.height)
                 || item.width < 1 || item.height < 1 || item.width > 16384 || item.height > 16384
                 || Object.keys(item).length !== 3) throw new Error("invalid geometry")
    }
  } else if (data.event === "phase") {
    if (["picking", "starting", "recording", "stopping", "screenshotting", "clipboard"].indexOf(data.phase) < 0)
      throw new Error("invalid phase")
  } else if (data.event === "saved") {
    if (!text(data.name, 128) || !/^(screenshot|screenrecording)-[0-9_-]+-[0-9a-f]{16}\.(png|mp4)$/.test(data.name)
        || !text(data.warning, 160)) throw new Error("invalid capture result")
  } else if (data.event === "error") {
    if (!text(data.message, 160)) throw new Error("invalid error")
  } else if (data.event !== "cancelled") throw new Error("unknown event")
  return data
}
if (typeof module !== "undefined") module.exports = {name, text, event}
