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
    if (s.na) return '<div class="status-chip status-chip-h"><span class="na-text">対象外</span></div>';
    var delay = isDelayed(s) ? '<span class="badge red">遅延</span>' : '';
    var actual = s.actual ? s.actual : '-';
    return '<div class="status-chip status-chip-h"><div class="badge-row"><span class="badge ' + COLOR[s.status] + '">' + LABEL[s.status] + '</span>' + delay + '</div>' +
      '<div class="dates-col"><div class="dates"><span>予：' + esc(s.plan || '-') + '</span></div>' +
      '<div class="dates"><span>実：' + esc(actual) + '</span></div></div></div>';
  }

  function overallKey(steps) {
    var applicable = steps.filter(function (s) { return !s.na; });
    if (applicable.length === 0) return 'na';
    var late = applicable.some(isDelayed);
    var all = applicable.length > 0 && applicable.every(function (s) { return s.status === 'done'; });
    var any = applicable.some(function (s) { return s.status === 'done' || s.status === 'progress'; });
    return late ? 'delay' : (all ? 'done' : (any ? 'progress' : 'wait'));
  }

  function overall(key) {
    if (key === 'na') return '<span class="na-text">対象外</span>';
    var label = { done: '完了', progress: '実施中', wait: '実施前', delay: '遅延' }[key];
    var color = { done: 'green', progress: 'blue', wait: 'gray', delay: 'red' }[key];
    return '<span class="badge overall-badge ' + color + '">' + label + '</span>';
  }

  var headRow = document.getElementById('headRow');
  var lastTh = headRow.lastElementChild;
  ProjectProgressStore.STEP_NAMES.forEach(function (name, i) {
    var th = document.createElement('th');
    th.textContent = (i + 1) + '：' + name;
    th.classList.add('no-sort');
    headRow.insertBefore(th, lastTh);
  });

  var body = document.getElementById('tbody');
  var projects = ProjectStore.load().filter(function (p) { return p.status !== '停止中'; });
  var rows = [];

  projects.forEach(function (p) {
    var rec = ProjectProgressStore.find(p.code);
    var key = overallKey(rec.steps);
    var customerName = CustomerStore.nameOf(p.customer);
    var managers = [p.pm].concat(p.pl || []).map(function (c) { return StaffStore.nameOf(c); }).filter(Boolean);
    var tr = document.createElement('tr');
    var html = '';
    html += '<td class="sticky" style="left:0;">' + esc(p.year) + '</td>';
    html += '<td class="sticky" style="left:90px;">' + esc(p.code) + '</td>';
    html += '<td class="sticky" style="left:240px;">' + esc(p.name) + '</td>';
    html += '<td class="sticky" style="left:460px;">' + esc(customerName) + '</td>';
    html += '<td class="sticky" style="left:660px;">' + managers.map(function (m) { return esc(m); }).join('<br>') + '</td>';
    html += '<td class="sticky" style="left:860px;">' + esc(p.startMonth) + '</td>';
    html += '<td class="sticky" style="left:960px;">' + overall(key) + '</td>';
    rec.steps.forEach(function (s) { html += '<td>' + chip(s) + '</td>'; });
    html += '<td class="row-actions"><a class="search-btn" href="project_progress_modify.html?id=' + encodeURIComponent(p.code) + '">編集</a></td>';
    tr.innerHTML = html;
    body.appendChild(tr);
    rows.push({
      tr: tr,
      year: p.year,
      code: p.code,
      name: p.name,
      customer: customerName,
      managers: managers,
      overall: key,
      month: p.startMonth || ''
    });
  });

  var uniq = function (arr) { return arr.filter(function (v, i) { return v && arr.indexOf(v) === i; }); };
  var customers = uniq(rows.map(function (r) { return r.customer; })).sort();
  var managerNames = uniq([].concat.apply([], rows.map(function (r) { return r.managers; }))).sort();
  var months = uniq(rows.map(function (r) { return r.month; })).sort();

  function setOptions(id, list) {
    document.getElementById(id).setAttribute('data-options', ['すべて'].concat(list).join(','));
  }
  setOptions('fCustomer', customers);
  setOptions('fManager', managerNames);

  var OVERALL_KEY = { '実施前': 'wait', '実施中': 'progress', '完了': 'done', '遅延': 'delay' };

  function val(id) {
    var el = document.getElementById(id);
    var v = el.getAttribute('data-value');
    if (v === null || v === '') v = el.textContent.replace('▾', '').trim();
    return v === 'すべて' ? '' : v;
  }

  function apply() {
    var kw = document.getElementById('fKeyword').value.trim().toLowerCase();
    var year = val('fYear');
    var customer = val('fCustomer');
    var manager = val('fManager');
    var overallLabel = val('fOverall');
    var shown = 0;

    rows.forEach(function (r) {
      var text = (r.code + ' ' + r.name + ' ' + r.customer + ' ' + r.managers.join(' ')).toLowerCase();
      var ok = (!kw || text.indexOf(kw) !== -1) &&
        (!year || r.year === year) &&
        (!customer || r.customer === customer) &&
        (!manager || r.managers.indexOf(manager) !== -1) &&
        (!overallLabel || r.overall === OVERALL_KEY[overallLabel]);
      r.tr.style.display = ok ? '' : 'none';
      r.tr.setAttribute('data-match', ok ? '1' : '0');
      if (ok) shown++;
    });

    document.getElementById('projectCount').textContent = shown;
    if (window.listPaginate) window.listPaginate(true);
  }

  document.getElementById('fSearch').addEventListener('click', apply);
  document.getElementById('fKeyword').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') apply();
  });

  document.getElementById('projectCount').textContent = projects.length;
})();
