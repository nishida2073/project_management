(function () {

  var body = document.getElementById('subjectBody');
  var list = SubjectStore.load();

  list.forEach(function (s) {
    var on = s.status !== OperatingStatusStore.labelOf('STOPPED');
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(s.code) + '</td>' +
      '<td><span class="tag ' + (SubjectTypeStore.colorOf(s.type) || '') + '">' + esc(SubjectTypeStore.nameOf(s.type)) + '</span></td>' +
      '<td>' + esc(s.name) + '</td>' +
      '<td><span class="badge overall-badge ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.labelOf('ACTIVE') : OperatingStatusStore.labelOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (s.memo ? ' title="' + esc(s.memo) + '"' : '') + '>' + (s.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="search-btn" href="subject_modify.html?id=' + encodeURIComponent(s.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('subjectCount').textContent = list.length;
})();
