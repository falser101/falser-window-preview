.pragma library

function waylandFor(toplevel) {
  return toplevel && toplevel.wayland ? toplevel.wayland : null
}

function appIdFor(toplevel) {
  var wayland = waylandFor(toplevel)
  if (wayland && wayland.appId)
    return String(wayland.appId)
  var ipc = toplevel && toplevel.lastIpcObject
  return String((ipc && (ipc.class || ipc.initialClass)) || "")
}

function titleFor(toplevel) {
  if (toplevel && toplevel.title)
    return String(toplevel.title)
  var wayland = waylandFor(toplevel)
  return String((wayland && wayland.title) || appIdFor(toplevel) || "Untitled")
}

function isEligible(toplevel) {
  var wayland = waylandFor(toplevel)
  if (!wayland)
    return false
  var ipc = toplevel && toplevel.lastIpcObject
  if (ipc && ipc.mapped === false)
    return false
  return true
}

function matchesFilter(toplevel, filterText) {
  var needle = String(filterText || "").trim().toLowerCase()
  if (!needle)
    return true
  var haystack = (appIdFor(toplevel) + " " + titleFor(toplevel)).toLowerCase()
  return haystack.indexOf(needle) !== -1
}

function isOnWorkspace(toplevel, workspace) {
  var toplevelWorkspace = toplevel && toplevel.workspace ? toplevel.workspace : null
  if (!toplevelWorkspace || !workspace)
    return false
  if (toplevelWorkspace === workspace)
    return true

  var toplevelId = Number(toplevelWorkspace.id)
  var workspaceId = Number(workspace.id)
  if (isFinite(toplevelId) && isFinite(workspaceId) && toplevelId !== 0 && workspaceId !== 0)
    return toplevelId === workspaceId

  var workspaceName = String(workspace.name || "")
  return Boolean(workspaceName) && String(toplevelWorkspace.name || "") === workspaceName
}

// Hyprland gives special workspaces (scratchpad, ...) negative ids.
function isSpecialWorkspaceId(workspaceId) {
  var id = Number(workspaceId)
  return isFinite(id) && id < 0
}

function isValidWorkspaceId(workspaceId) {
  var id = Number(workspaceId)
  return isFinite(id) && id !== 0
}

function workspaceLabel(workspaces, workspaceId) {
  var id = Number(workspaceId)
  if (isSpecialWorkspaceId(id)) {
    var workspace = workspaceById(workspaces, id)
    var name = String((workspace && workspace.name) || "special")
    return name.replace(/^special:/, "") || "special"
  }
  return id === 10 ? "0" : String(id)
}

function isOnWorkspaceId(toplevel, workspaceId) {
  var toplevelWorkspace = toplevel && toplevel.workspace ? toplevel.workspace : null
  if (!toplevelWorkspace)
    return false
  return Number(toplevelWorkspace.id) === Number(workspaceId)
}

function collect(toplevels, filterText, workspaceId) {
  var out = []
  var values = toplevels || []
  var hasWorkspace = isValidWorkspaceId(workspaceId)
  for (var i = 0; i < values.length; i++) {
    var top = values[i]
    if (!isEligible(top))
      continue
    if (hasWorkspace && !isOnWorkspaceId(top, workspaceId))
      continue
    if (!matchesFilter(top, filterText))
      continue
    out.push(top)
  }
  return out
}

function countOnWorkspace(toplevels, workspaceId) {
  var values = toplevels || []
  var count = 0
  for (var i = 0; i < values.length; i++) {
    if (!isEligible(values[i]))
      continue
    if (isOnWorkspaceId(values[i], workspaceId))
      count++
  }
  return count
}

function workspaceIds(workspaces, minSlots) {
  var ids = []
  var slots = Math.max(1, Number(minSlots) || 5)
  for (var n = 1; n <= slots; n++)
    ids.push(n)

  var specialIds = []
  var values = workspaces || []
  for (var i = 0; i < values.length; i++) {
    var id = Number(values[i].id)
    if (id > 0 && id <= 10 && ids.indexOf(id) === -1)
      ids.push(id)
    else if (isSpecialWorkspaceId(id) && specialIds.indexOf(id) === -1)
      specialIds.push(id)
  }

  ids.sort(function(left, right) { return left - right })
  // Special workspaces follow the numbered ones, most recent first.
  specialIds.sort(function(left, right) { return right - left })
  return ids.concat(specialIds)
}

function workspaceById(workspaces, id) {
  var values = workspaces || []
  var target = Number(id)
  for (var i = 0; i < values.length; i++) {
    if (Number(values[i].id) === target)
      return values[i]
  }
  return null
}

function aspectRatioFor(toplevel) {
  var g = geometryFor(toplevel)
  return Math.max(0.45, Math.min(4, g.w / g.h))
}

function geometryFor(toplevel) {
  var ipc = toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : {}
  var at = ipc.at || [0, 0]
  var size = ipc.size || [0, 0]
  var w = Number(size[0])
  var h = Number(size[1])
  return {
    x: Number(at[0]) || 0,
    y: Number(at[1]) || 0,
    w: (isFinite(w) && w > 0) ? w : 800,
    h: (isFinite(h) && h > 0) ? h : 600,
    floating: ipc.floating === true
  }
}

function layoutName(workspace) {
  if (!workspace)
    return ""
  var ipc = workspace.lastIpcObject
  if (ipc && ipc.tiledLayout)
    return String(ipc.tiledLayout)
  if (workspace.tiledLayout)
    return String(workspace.tiledLayout)
  return ""
}

function emptyLayout(areaW, areaH) {
  return {
    slots: [],
    contentW: Math.max(1, areaW),
    contentH: Math.max(1, areaH),
    mode: "empty",
    columns: 1,
    rows: 1
  }
}

function chooseColumns(count, areaW, areaH) {
  var n = Math.max(1, Number(count) || 1)
  if (n === 1)
    return 1
  if (n === 2)
    return (areaW / Math.max(areaH, 1)) >= 1.15 ? 2 : 1

  var areaAspect = areaW / Math.max(areaH, 1)
  var bestCols = 1
  var bestScore = -Infinity

  for (var cols = 1; cols <= n; cols++) {
    var rows = Math.ceil(n / cols)
    var cellW = areaW / cols
    var cellH = areaH / rows
    if (cellW < 96 || cellH < 72)
      continue

    var cellAspect = cellW / Math.max(cellH, 1)
    // Prefer cells near a typical window aspect, with fewer holes in the last row.
    var score = -Math.abs(Math.log(cellAspect / Math.max(areaAspect, 0.5)))
    score -= (cols * rows - n) * 0.35
    // Mild preference for wider grids on wide screens.
    score += Math.min(cols, 4) * 0.02

    if (score > bestScore) {
      bestScore = score
      bestCols = cols
    }
  }

  return bestCols
}

// Fit every window on one screen: pick columns, wrap rows, shrink cells.
function responsiveGridLayout(items, areaW, areaH, gap) {
  var n = items.length
  // Larger gaps when few tiles (two full-width apps must not touch).
  var baseGap = Math.max(0, Number(gap) || 12)
  var spacing = n <= 2 ? Math.max(baseGap, 56) : (n <= 4 ? Math.max(baseGap, 28) : Math.max(baseGap, 16))

  // Shrink the usable pack area so cards sit inset with breathing room.
  // Two stacked full-width apps need stronger inset + gap.
  var fillW = n <= 2 ? 0.80 : (n <= 4 ? 0.88 : 0.92)
  var fillH = n <= 2 ? 0.76 : (n <= 4 ? 0.86 : 0.92)
  var innerW = Math.max(1, areaW * fillW)
  var innerH = Math.max(1, areaH * fillH)

  var cols = chooseColumns(n, innerW, innerH)
  var rows = Math.ceil(n / cols)
  var cellW = (innerW - spacing * Math.max(0, cols - 1)) / cols
  var cellH = (innerH - spacing * Math.max(0, rows - 1)) / rows

  // Keep a pleasant minimum, then reflow with more columns if needed.
  var guard = 0
  while (guard < 6 && (cellW < 110 || cellH < 88) && cols < n) {
    cols += 1
    rows = Math.ceil(n / cols)
    cellW = (innerW - spacing * Math.max(0, cols - 1)) / cols
    cellH = (innerH - spacing * Math.max(0, rows - 1)) / rows
    guard += 1
  }

  var gridW = cols * cellW + spacing * Math.max(0, cols - 1)
  var gridH = rows * cellH + spacing * Math.max(0, rows - 1)
  var ox = Math.max(0, (areaW - gridW) / 2)
  var oy = Math.max(0, (areaH - gridH) / 2)

  var slots = []
  for (var i = 0; i < n; i++) {
    var col = i % cols
    var row = Math.floor(i / cols)
    var lastRowCount = n - row * cols
    var rowOffsetX = 0
    // Center a short final row for balance.
    if (row === rows - 1 && lastRowCount < cols)
      rowOffsetX = ((cols - lastRowCount) * (cellW + spacing)) / 2

    slots.push({
      top: items[i].top,
      x: ox + rowOffsetX + col * (cellW + spacing),
      y: oy + row * (cellH + spacing),
      w: cellW,
      h: cellH
    })
  }

  return {
    slots: slots,
    contentW: areaW,
    contentH: areaH,
    mode: "responsive-grid",
    columns: cols,
    rows: rows
  }
}

function buildLayout(toplevels, workspace, areaW, areaH, gap) {
  var width = Math.max(1, Number(areaW) || 1)
  var height = Math.max(1, Number(areaH) || 1)
  var spacing = Math.max(0, Number(gap) || 12)
  var values = toplevels || []
  if (values.length === 0)
    return emptyLayout(width, height)

  var items = []
  for (var i = 0; i < values.length; i++)
    items.push({ top: values[i], g: geometryFor(values[i]) })

  // Stable visual order: left-to-right, top-to-bottom on the real desktop.
  items.sort(function(a, b) {
    return a.g.x - b.g.x || a.g.y - b.g.y
  })

  return responsiveGridLayout(items, width, height, spacing)
}
