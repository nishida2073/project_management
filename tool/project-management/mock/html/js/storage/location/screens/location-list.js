(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  var TYPE_CLASS = {};
  LocationTypeStore.load().forEach(function (t) { TYPE_CLASS[t.code] = t.color; });

  var body = document.getElementById('locationBody');
  var list = LocationStore.load();

  list.forEach(function (l) {
    var on = l.status !== '停止中';
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(l.code) + '</td>' +
      '<td><span class="tag ' + (TYPE_CLASS[l.type] || '') + '">' + esc(LocationTypeStore.nameOf(l.type)) + '</span></td>' +
      '<td>' + esc(l.name) + '</td>' +
      '<td>' + esc(l.tel) + '</td>' +
      '<td>' + esc(l.address) + '</td>' +
      '<td><span class="badge overall-badge ' + (on ? 'green' : 'gray') + '">' + (on ? '稼働中' : '停止中') + '</span></td>' +
      '<td class="row-actions"><a class="search-btn" href="location_modify.html?id=' + encodeURIComponent(l.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('locationCount').textContent = list.length;
})();
