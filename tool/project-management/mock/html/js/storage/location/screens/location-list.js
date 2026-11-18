(function () {
  var TYPE_CLASS = {};
  LocationTypeStore.load().forEach(function (t) { TYPE_CLASS[t.code] = t.color; });

  var body = document.getElementById('locationBody');
  var list = LocationStore.load();

  list.forEach(function (l) {
    var on = l.status !== OperatingStatusStore.nameOf('STOPPED');
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(l.code) + '</td>' +
      '<td><span class="tag kind-tag ' + (TYPE_CLASS[l.type] || '') + '">' + esc(LocationTypeStore.nameOf(l.type)) + '</span></td>' +
      '<td>' + esc(l.name) + '</td>' +
      '<td>' + esc(l.tel) + '</td>' +
      '<td>' + esc(l.address) + '</td>' +
      '<td><span class="status-label ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.nameOf('ACTIVE') : OperatingStatusStore.nameOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (l.memo ? ' title="' + esc(l.memo) + '"' : '') + '>' + (l.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="search-btn" href="location_modify.html?id=' + encodeURIComponent(l.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('locationCount').textContent = list.length;
})();
