.pragma library

function filterList(list, needle) {
  var src = list || []
  if (!needle) return src
  var n = String(needle).toLowerCase()
  return src.filter(function (item) { return String(item).toLowerCase().indexOf(n) >= 0 })
}

function fmtCell(v) {
  if (v === null || v === undefined) return "NULL"
  return String(v)
}

function isNull(v) {
  return v === null || v === undefined
}

function computeWidths(cols, rows, charW, minW, maxW, pad) {
  var widths = []
  for (var c = 0; c < cols.length; c++) {
    var max = String(cols[c]).length
    var sample = Math.min(rows ? rows.length : 0, 50)
    for (var r = 0; r < sample; r++) {
      var row = rows[r]
      if (row && c < row.length) {
        var len = isNull(row[c]) ? 4 : String(row[c]).length
        if (len > max) max = len
      }
    }
    var w = max * charW + pad
    if (w < minW) w = minW
    if (w > maxW) w = maxW
    widths.push(Math.round(w))
  }
  return widths
}

function rangeLabel(offset, shown, total, truncated) {
  if (!shown) return "no rows"
  var from = offset + 1
  var to = offset + shown
  if (truncated) return from + "–" + to + " (capped)"
  return from + "–" + to + " of " + total
}

function parseEngine(raw) {
  try {
    var data = JSON.parse(raw)
    return { ok: true, data: data }
  } catch (e) {
    return { ok: false, error: "bad engine output: " + e }
  }
}
