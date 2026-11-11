(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  var body = document.getElementById('subjectBody');
  var list = SubjectStore.load();

  list.forEach(function (s) {
    var on = s.status !== '停止中';
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(s.code) + '</td>' +
      '<td><span class="tag ' + (SubjectTypeStore.colorOf(s.type) || '') + '">' + esc(SubjectTypeStore.nameOf(s.type)) + '</span></td>' +
      '<td>' + esc(s.name) + '</td>' +
      '<td><span class="state ' + (on ? 'on' : 'off') + '"><span class="dot"></span>' + (on ? '稼働中' : '停止中') + '</span></td>' +
      '<td><a class="search-btn" href="subject_modify.html?id=' + encodeURIComponent(s.code) + '">編集</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('subjectCount').textContent = list.length;
})();
