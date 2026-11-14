(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  var body = document.getElementById('vendorBody');
  var list = TeacherVenderStore.load();

  list.forEach(function (v) {
    var on = v.status !== '停止中';
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(v.code) + '</td>' +
      '<td>' + esc(v.name) + '</td>' +
      '<td>' + esc(v.tel) + '</td>' +
      '<td>' + esc(v.contactName) + '</td>' +
      '<td><span class="badge overall-badge ' + (on ? 'green' : 'gray') + '">' + (on ? '稼働中' : '停止中') + '</span></td>' +
      '<td class="memo-cell"' + (v.memo ? ' title="' + esc(v.memo) + '"' : '') + '>' + (v.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="search-btn" href="teacher_vender_modify.html?id=' + encodeURIComponent(v.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('vendorCount').textContent = list.length;
})();
