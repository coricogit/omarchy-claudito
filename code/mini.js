.pragma library

// Seasonal clothes for the tiny Claudito (the bar icon): the small version of
// the seasonal HATS and OUTFITS in sprites.js. "." is transparent.

var HAT_TOP = -3      // rows above the head; the last one covers its top
var OUTFIT_TOP = 8    // rows of the body

var HATS = {
  spring: {
    palette: { p: "#F783AC", w: "#FFFFFF", v: "#B197FC", y: "#FFD43B", g: "#2F9E44", L: "#69DB7C" },
    rows: [
      "................",
      "...p....w....v..",
      "..pyp..wyw..vyv.",
      "..gpggLgwgLggvg."
    ]
  },
  summer: {
    palette: { s: "#F2D388", S: "#E0B84C", k: "#B58B2A", r: "#E03131" },
    rows: [
      "......kkkkk.....",
      ".....sSsSsSs....",
      ".....rrrrrrr....",
      ".sSsSsSsSsSsSsSs"
    ]
  },
  autumn: {
    palette: { c: "#C68642", C: "#A5662B", d: "#6B3F16", s: "#4A2C17", o: "#F76707", O: "#D9480F" },
    rows: [
      ".......ss..o....",
      "......cCcCooo...",
      "....cCcCcCcOc...",
      "..ddddddddddddd."
    ]
  },
  winter: {
    palette: { w: "#F8F9FA", g: "#CED4DA", t: "#1C7ED6", T: "#1864AB" },
    rows: [
      ".......www......",
      "......ttttt.....",
      "....ttTttTttt...",
      "..wgwgwgwgwgwgw."
    ]
  }
}

var OUTFITS = {
  spring: {
    palette: { g: "#69DB7C", G: "#2F9E44", y: "#FFD43B", p: "#F783AC" },
    rows: [
      "...G.........G..",
      "...GgggpypgggG..",
      ".Gggggggggggggg."
    ]
  },
  summer: {
    palette: { b: "#15AABF", c: "#E3FAFC", y: "#FFD43B", p: "#FF8FB8" },
    rows: [
      ".bbbbcc...ccbbb.",
      ".bybbbbcccbbbpb.",
      ".bbbpbbbcbbybbb."
    ]
  },
  autumn: {
    palette: { m: "#8C2F39", z: "#F2B134" },
    rows: [
      ".mmmmmmmmmmmmmm.",
      ".mzmzmzmzmzmzmz.",
      ".mmmmmmmmmmmmmm."
    ]
  },
  winter: {
    palette: { r: "#E03131", w: "#F8F9FA", d: "#8E1B1B" },
    rows: [
      ".rrwwrrwwrrwwrr.",
      ".dddddddddddddd.",
      ".........drrd..."
    ]
  }
}

// A third darker, like the shaded left side of the body.
function shade(hex) {
  var out = "#"
  for (var i = 1; i < 7; i += 2) {
    var v = Math.round(parseInt(hex.slice(i, i + 2), 16) / 1.3).toString(16)
    out += v.length < 2 ? "0" + v : v
  }
  return out
}

function add(out, sprite, top, shaded) {
  for (var y = 0; y < sprite.rows.length; y++)
    for (var x = 0; x < sprite.rows[y].length; x++) {
      var ch = sprite.rows[y][x]
      if (ch === ".") continue
      var c = sprite.palette[ch]
      out.push([x, top + y, shaded && x === 1 ? shade(c) : c])
    }
}

// [[x, y, color], ...] for MiniClaudito. `hat` and `outfit` are seasons, or
// "" for none.
function clothes(hat, outfit) {
  var out = []
  if (OUTFITS[outfit]) add(out, OUTFITS[outfit], OUTFIT_TOP, true)
  if (HATS[hat]) add(out, HATS[hat], HAT_TOP, false)
  return out
}
