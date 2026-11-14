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
    var actual = s.actual ? s.actual : '-';
    return '<div class="status-chip status-chip-h"><div class="badge-row"><span class="badge ' + COLOR[s.status] + '">' + LABEL[s.status] + '</span></div>' +
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
    var label = { done: '完了', progress: '進行中', wait: '未着手', delay: '遅延' }[key];
    var color = { done: 'green', progress: 'blue', wait: 'gray', delay: 'red' }[key];
    return '<span class="badge overall-badge ' + color + '">' + label + '</span>';
  }

  var headRow = document.getElementById('headRow');
  var overallTh = headRow.querySelector('th.col-overall');
  while (overallTh.nextElementSibling) headRow.removeChild(overallTh.nextElementSibling);
  ProjectProgressStore.STEP_NAMES.forEach(function (name, i) {
    var th = document.createElement('th');
    th.style.minWidth = '230px';
    th.classList.add('no-sort');
    th.textContent = (i + 1) + '：' + name;
    headRow.appendChild(th);
  });
  var operationTh = document.createElement('th');
  operationTh.textContent = '操作';
  operationTh.className = 'col-actions';
  headRow.appendChild(operationTh);

  var body = document.getElementById('tbody');
  var projects = ProjectStore.load().filter(function (p) { return p.status !== '停止中'; });
  var rows = [];

  projects.forEach(function (p) {
    var rec = ProjectProgressStore.find(p.code);
    var key = overallKey(rec.steps);
    var customerName = CustomerStore.nameOf(p.customer);
    var managers = [p.pm].concat(p.pl || []).map(function (c) { return StaffStore.nameOf(c); }).filter(Boolean);
    var tr = document.createElement('tr');
    tr.setAttribute('data-id', p.code);
    var html = '';
    html += '<td class="sticky col-year">' + esc(String(p.year).replace('年度', '') + '年度') + '</td>';
    html += '<td class="sticky">' + esc(p.code) + '</td>';
    html += '<td class="sticky">' + esc(p.name) + '</td>';
    html += '<td class="sticky col-customer">' + esc(customerName) + '</td>';
    html += '<td class="sticky col-manager">' + managers.map(function (m) { return esc(m); }).join('<br>') + '</td>';
    html += '<td class="sticky">' + esc(p.startMonth) + '</td>';
    html += '<td class="sticky col-overall">' + overall(key) + '</td>';
    rec.steps.forEach(function (s, si) {
      var classes = [];
      if (isDelayed(s)) classes.push('is-delay');
      if (s.memo) classes.push('has-memo');
      var attrs = (classes.length ? ' class="' + classes.join(' ') + '"' : '') + (s.memo ? ' title="' + esc(s.memo) + '"' : '');
      html += '<td data-step="' + si + '"' + attrs + '>' + chip(s) + '</td>';
    });
    html += '<td class="row-actions"><a class="search-btn" href="project_progress_modify.html?id=' + encodeURIComponent(p.code) + '">更新</a></td>';
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

  var OVERALL_KEY = { '未着手': 'wait', '進行中': 'progress', '完了': 'done', '遅延': 'delay' };

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
        (!year || String(r.year).indexOf(year) !== -1) &&
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
  var P_STATUS_OF_LABEL = { '実施前': 'wait', '実施中': 'progress', '完了': 'done' };
  var P_LABEL_OF_STATUS = { wait: '実施前', progress: '実施中', done: '完了' };
  var P_STATUS_COLOR_OF = { done: 'green', progress: 'blue', wait: 'gray' };
  function pOwnText(el) {
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; }).map(function (n) { return n.textContent; }).join('').trim();
  }
  function pValueOf(el) {
    var v = el.getAttribute('data-value');
    if (v === null || v === '') v = pOwnText(el);
    v = String(v || '').trim();
    return v === '選択してください' ? '' : v;
  }
  function openProjectStepDialog(projectCode, i) {
    var rec = ProjectProgressStore.find(projectCode);
    var sv = rec.steps[i] || {};
    var proj = ProjectStore.map()[projectCode] || {};
    var projInfo = (proj.name || '') + '　' + projectCode + '　' + (proj.startMonth || '');
    var stepName = ProjectProgressStore.STEP_NAMES[i];
    var overlay = document.createElement('div');
    overlay.className = 'overlay';
    overlay.innerHTML = '<div class="input-dialog">' +
      '<div class="input-dialog-title">' + esc((i + 1) + '：' + stepName) + '</div>' +
      '<div style="font-size:12px;color:#6c7688;margin-bottom:8px;">' + esc(projInfo) + '</div>' +
      '<label class="input-dialog-label">予定日</label>' +
      '<div class="form-control js-date" id="pdPlan">' + esc(sv.plan || '') + '<span class="caret">▾</span></div>' +
      '<label class="input-dialog-label">実施日</label>' +
      '<div class="form-control js-date" id="pdActual">' + esc(sv.actual || '') + '<span class="caret">▾</span></div>' +
      '<label class="input-dialog-label">状態</label>' +
      '<div class="status-select status-combo ' + P_STATUS_COLOR_OF[sv.status || 'wait'] + ' js-select" id="pdStatus" data-options="実施前,実施中,完了" data-class-map=\'{"実施前":"gray","実施中":"blue","完了":"green"}\' data-value="' + esc(P_LABEL_OF_STATUS[sv.status || 'wait']) + '">' + esc(P_LABEL_OF_STATUS[sv.status || 'wait']) + '<span class="caret">▾</span></div>' +
      '<label class="input-dialog-label">備考</label>' +
      '<textarea class="form-control textarea" id="pdMemo" rows="2">' + esc(sv.memo || '') + '</textarea>' +
      '<div class="input-dialog-actions"><div class="search-btn pd-cancel">キャンセル</div><div class="btn primary pd-ok">保存</div></div></div>';
    document.body.appendChild(overlay);
    overlay.querySelectorAll('.js-select').forEach(function (el) { window.bindJsSelect(el); });
    overlay.querySelectorAll('.js-date').forEach(function (el) { window.bindDatePicker(el); });
    function close() { overlay.remove(); }
    overlay.querySelector('.pd-cancel').addEventListener('click', close);
    overlay.addEventListener('click', function (e) { if (e.target === overlay) close(); });
    overlay.querySelector('.pd-ok').addEventListener('click', function () {
      var steps = ProjectProgressStore.find(projectCode).steps.slice();
      steps[i] = Object.assign({}, steps[i] || {}, {
        status: P_STATUS_OF_LABEL[pValueOf(overlay.querySelector('#pdStatus'))] || 'wait',
        plan: pOwnText(overlay.querySelector('#pdPlan')),
        actual: pOwnText(overlay.querySelector('#pdActual')),
        memo: overlay.querySelector('#pdMemo').value
      });
      ProjectProgressStore.upsert({ projectCode: projectCode, steps: steps });
      location.reload();
    });
  }
  body.addEventListener('click', function (e) {
    var td = e.target.closest('td[data-step]');
    if (!td || td.textContent.indexOf('対象外') !== -1) return;
    openProjectStepDialog(td.parentNode.getAttribute('data-id'), Number(td.getAttribute('data-step')));
  });
})();
