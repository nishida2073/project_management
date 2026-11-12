(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  var body = document.getElementById('staffVenderBody');
  var list = StaffVenderStore.load();

  list.forEach(function (c) {
    var on = c.status !== '停止中';
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(c.code) + '</td>' +
      '<td>' + esc(c.name) + '</td>' +
      '<td>' + esc(c.tel) + '</td>' +
      '<td>' + esc(c.address) + '</td>' +
      '<td>' + esc(c.contactName) + '</td>' +
      '<td><span class="badge overall-badge ' + (on ? 'green' : 'gray') + '">' + (on ? '稼働中' : '停止中') + '</span></td>' +
      '<td class="row-actions"><a class="search-btn" href="staff_vender_modify.html?id=' + encodeURIComponent(c.code) + '">編集</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('staffVenderCount').textContent = list.length;
})();
