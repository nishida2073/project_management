(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  var LABEL = { wait: '実施前', progress: '実施中', done: '完了' };
  var COLOR = { wait: 'gray', progress: 'blue', done: 'green' };
  var today = new Date();
  today.setHours(0, 0, 0, 0);

  function isDelayed(s) {
    if (s.na || s.status === 'done' || !s.plan) return false;
    var plan = new Date(String(s.plan).replace(/\//g, '-'));
    return !isNaN(plan.getTime()) && plan < today;
  }

  function chip(s) {
    if (s.na) return '<div class="status-chip"><span class="badge na">実施対象外</span></div>';
    var delay = isDelayed(s) ? '<span class="badge red">⚠ 遅延</span>' : '';
    var dates = '<div class="dates"><span>予定 ' + esc(s.plan || '-') + '</span>' + (s.actual ? '<span>実績 ' + esc(s.actual) + '</span>' : '') + '</div>';
    return '<div class="status-chip"><div class="badge-row"><span class="badge ' + COLOR[s.status] + '">' + LABEL[s.status] + '</span>' + delay + '</div>' + dates + '</div>';
  }

  function overall(steps) {
    var applicable = steps.filter(function (s) { return !s.na; });
    var late = applicable.some(isDelayed);
    var all = applicable.length > 0 && applicable.every(function (s) { return s.status === 'done'; });
    var any = applicable.some(function (s) { return s.status === 'done' || s.status === 'progress'; });
    var key = late ? 'delay' : (all ? 'done' : (any ? 'progress' : 'wait'));
    var label = { done: '完了', progress: '実施中', wait: '実施前', delay: '遅延あり' }[key];
    var color = { done: 'green', progress: 'blue', wait: 'gray', delay: 'red' }[key];
    return '<span class="overall ' + color + '">' + label + '</span>';
  }

  var headRow = document.getElementById('headRow');
  var lastTh = headRow.lastElementChild;
  ProjectProgressStore.STEP_NAMES.forEach(function (name) {
    var th = document.createElement('th');
    th.textContent = name;
    headRow.insertBefore(th, lastTh);
  });

  var body = document.getElementById('tbody');
  var projects = ProjectStore.load();

  projects.forEach(function (p) {
    var rec = ProjectProgressStore.find(p.code);
    var tr = document.createElement('tr');
    var html = '';
    html += '<td class="sticky" style="left:0;">' + esc(p.year) + '</td>';
    html += '<td class="sticky" style="left:90px; font-weight:700;">' + esc(p.code) + '</td>';
    html += '<td class="sticky" style="left:240px;">' + esc(p.name) + '</td>';
    html += '<td class="sticky" style="left:460px;">' + esc(CustomerStore.nameOf(p.customer)) + '</td>';
    html += '<td class="sticky" style="left:570px;">' + esc(StaffStore.nameOf(p.pm)) + (p.pl && p.pl.length ? ' / ' + esc(p.pl.map(function (c) { return StaffStore.nameOf(c); }).join(' / ')) : '') + '</td>';
    html += '<td class="sticky" style="left:770px;">' + esc(p.startMonth) + '</td>';
    html += '<td class="sticky shadow" style="left:870px;">' + overall(rec.steps) + '</td>';
    rec.steps.forEach(function (s) { html += '<td>' + chip(s) + '</td>'; });
    html += '<td class="row-actions"><a class="search-btn" href="project_progress_modify.html?id=' + encodeURIComponent(p.code) + '">編集</a></td>';
    tr.innerHTML = html;
    body.appendChild(tr);
  });

  document.getElementById('projectCount').textContent = projects.length;
})();
