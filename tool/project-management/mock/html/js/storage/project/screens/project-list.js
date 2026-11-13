(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function managerTag(positionCode, staffCode) {
    var name = StaffStore.nameOf(staffCode);
    if (!name) return '';
    return '<span class="tag ' + PositionStore.colorOf(positionCode) + '">' + esc(PositionStore.nameOf(positionCode)) + '</span> ' + esc(name);
  }

  var body = document.getElementById('projectBody');
  var list = ProjectStore.load();

  list.forEach(function (p) {
    var tr = document.createElement('tr');
    var managerList = [managerTag('PS-01', p.pm)].concat((p.pl || []).map(function (c) { return managerTag('PS-02', c); })).filter(Boolean);
    tr.innerHTML =
      '<td>' + esc(p.year) + '</td>' +
      '<td>' + esc(p.code) + '</td>' +
      '<td><span class="tag ' + SalesTypeStore.colorOf(p.sales) + '">' + esc(SalesTypeStore.nameOf(p.sales)) + '</span></td>' +
      '<td><span class="tag ' + ParticipationTypeStore.colorOf(p.part) + '">' + esc(ParticipationTypeStore.nameOf(p.part)) + '</span></td>' +
      '<td>' + esc(p.name) + '</td>' +
      '<td>' + esc(CustomerStore.nameOf(p.customer)) + '</td>' +
      '<td>' + managerList.join('<br>') + '</td>' +
      '<td>' + esc(p.startMonth) + '</td>' +
      '<td><span class="badge overall-badge ' + (p.status === '停止中' ? 'gray' : 'green') + '">' + (p.status === '停止中' ? '停止中' : '稼働中') + '</span></td>' +
      '<td class="row-actions"><a class="search-btn" href="project_modify.html?id=' + encodeURIComponent(p.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('projectCount').textContent = list.length;

  var managerSelect = document.getElementById('managerFilter');
  if (managerSelect) {
    managerSelect.setAttribute('data-options', ['すべて'].concat(StaffStore.candidates({
      includeStopped: true, affiliations: ['社内'], roles: ['案件'], jobTypes: ['販売']
    })).join(','));
  }
})();
