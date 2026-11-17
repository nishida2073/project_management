(function () {

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
      '<td>' + esc(yearLabel(p.year)) + '</td>' +
      '<td>' + esc(p.code) + '</td>' +
      '<td><span class="tag ' + SalesTypeStore.colorOf(p.sales) + '">' + esc(SalesTypeStore.nameOf(p.sales)) + '</span></td>' +
      '<td><span class="tag ' + ParticipationTypeStore.colorOf(p.part) + '">' + esc(ParticipationTypeStore.nameOf(p.part)) + '</span></td>' +
      '<td>' + esc(p.name) + '</td>' +
      '<td>' + esc(CustomerStore.nameOf(p.customer)) + '</td>' +
      '<td>' + managerList.join('<br>') + '</td>' +
      '<td>' + esc(p.startMonth) + '</td>' +
      '<td><span class="badge overall-badge ' + (p.status === OperatingStatusStore.labelOf('STOPPED') ? 'gray' : 'green') + '">' + (p.status === OperatingStatusStore.labelOf('STOPPED') ? OperatingStatusStore.labelOf('STOPPED') : OperatingStatusStore.labelOf('ACTIVE')) + '</span></td>' +
      '<td class="memo-cell"' + (p.memo ? ' title="' + esc(p.memo) + '"' : '') + '>' + (p.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="search-btn" href="project_modify.html?id=' + encodeURIComponent(p.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('projectCount').textContent = list.length;

  var managerSelect = document.getElementById('managerFilter');
  if (managerSelect) {
    managerSelect.setAttribute('data-options', ['すべて'].concat(StaffStore.candidates({
      includeStopped: true, affiliations: [AffiliationStore.nameOf('INTERNAL')], roles: ['案件'], jobTypes: [JobTypeStore.nameOf('JT-01')]
    })).join(','));
  }
})();
