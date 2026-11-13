(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  var ROLE_CLASS = {};
  StaffRoleStore.load().forEach(function (t) { ROLE_CLASS[t.code] = t.color; });
  var JOB_CLASS = {};
  JobTypeStore.load().forEach(function (t) { JOB_CLASS[t.code] = t.color; });
  var POS_CLASS = {};
  PositionStore.load().forEach(function (t) { POS_CLASS[t.code] = t.color; });

  var body = document.getElementById('staffBody');
  var list = StaffStore.load();

  list.forEach(function (t) {
    var on = t.status !== '停止中';
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(t.code) + '</td>' +
      '<td><span class="tag ' + (t.affiliation === 'パートナー' ? 'orange' : 'blue') + '">' + esc(t.affiliation) + '</span></td>' +
      '<td>' + (t.company ? esc(StaffVenderStore.nameOf(t.company)) : '-') + '</td>' +
      '<td>' + esc(t.name) + '</td>' +
      '<td>' + esc(t.email) + '</td>' +
      '<td>' + (t.roles || []).map(function (r) { return '<span class="tag ' + (ROLE_CLASS[r] || '') + '">' + esc(StaffRoleStore.nameOf(r)) + '</span>'; }).join(' ') + '</td>' +
      '<td>' + (t.jobTypes || []).map(function (j) { return '<span class="tag ' + (JOB_CLASS[j] || '') + '">' + esc(JobTypeStore.nameOf(j)) + '</span>'; }).join(' ') + '</td>' +
      '<td>' + ((t.positions || []).length ? (t.positions || []).map(function (p) { return '<span class="tag ' + (POS_CLASS[p] || '') + '">' + esc(PositionStore.nameOf(p)) + '</span>'; }).join(' ') : '-') + '</td>' +
      '<td><span class="badge overall-badge ' + (on ? 'green' : 'gray') + '">' + (on ? '稼働中' : '停止中') + '</span></td>' +
      '<td class="row-actions"><a class="search-btn" href="staff_modify.html?id=' + encodeURIComponent(t.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('staffCount').textContent = list.length;
})();
