.pragma library

// Text for a notification body, shown as it is. The shell decodes entities
// there and then draws some tags, so escaping does not help: a zero-width
// space keeps either from forming.
function plain(text) {
  return String(text || "").replace(/[&<]/g, "$&​")
}
