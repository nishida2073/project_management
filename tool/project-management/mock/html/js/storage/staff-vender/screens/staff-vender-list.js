(function () {
  var body = document.getElementById('staffVenderBody');
  var list = StaffVenderStore.load();

  list.forEach(function (c) {
    var on = c.status !== OperatingStatusStore.nameOf('STOPPED');
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(c.code) + '</td>' +
      '<td>' + esc(c.name) + '</td>' +
      '<td>' + esc(c.tel) + '</td>' +
      '<td>' + esc(c.address) + '</td>' +
      '<td>' + esc(c.contactName) + '</td>' +
      '<td><span class="badge overall-badge ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.nameOf('ACTIVE') : OperatingStatusStore.nameOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (c.memo ? ' title="' + esc(c.memo) + '"' : '') + '>' + (c.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="search-btn" href="staff_vender_modify.html?id=' + encodeURIComponent(c.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('staffVenderCount').textContent = list.length;
})();
