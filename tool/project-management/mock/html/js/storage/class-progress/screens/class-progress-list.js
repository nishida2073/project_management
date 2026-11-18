(function () {
  (function buildTaskTypeTabs() {
    var container = document.getElementById('taskTypeTabs');
    if (!container) return;
    TaskTypeStore.load().forEach(function (t) {
      var tab = document.createElement('span');
      tab.className = 'year-tab';
      tab.setAttribute('data-tt', t.name);
      tab.setAttribute('data-code', t.code);
      tab.textContent = t.name;
      container.appendChild(tab);
    });
  })();

  var SORTED = TaskStore.load().slice().sort(function (a, b) {
    var ka = a.kinds[0] || '';
    var kb = b.kinds[0] || '';
    if (ka !== kb) return ka < kb ? -1 : 1;
    return a.order - b.order;
  });
  var STEP_NAMES = SORTED.map(function (t) { return t.name; });
  function isActive(i) { return SORTED[i].status !== OperatingStatusStore.nameOf('STOPPED'); }
  var DISPLAY_NO = [];
  (function () {
    var counts = {};
    SORTED.forEach(function (t, i) {
      if (t.status === OperatingStatusStore.nameOf('STOPPED')) return;
      var k = t.kinds[0] || '';
      counts[k] = (counts[k] || 0) + 1;
      DISPLAY_NO[i] = counts[k];
    });
  })();
  var STATUS_LABEL = StepStatusStore.nameByCode();
  var STATUS_CLASS = { DONE: 'green', PROGRESS: 'blue', WAIT: 'gray' };

  var today = new Date();
  today.setHours(0, 0, 0, 0);

  function addDays(base, days) {
    var d = new Date(base);
    d.setDate(d.getDate() + days);
    return d.getFullYear() + '/' + pad2(d.getMonth() + 1) + '/' + pad2(d.getDate());
  }

  function isDelayed(step) {
    if (step.na) return false;
    if (step.status === 'DONE' || !step.plan) return false;
    var plan = new Date(String(step.plan).replace(/\//g, '-'));
    return !isNaN(plan.getTime()) && plan < today;
  }

  function chip(step) {
    if (step.kindNa) return '';
    if (step.na) return '<div class="status-chip status-chip-h"><span class="na-text">' + StepStatusStore.nameOf('NA') + '</span></div>';
    var label = STATUS_LABEL[step.status] || StepStatusStore.nameOf('WAIT');
    var cls = STATUS_CLASS[step.status] || 'gray';
    var actual = step.actual ? step.actual : '-';
    return '<div class="status-chip status-chip-h"><div class="status-row"><span class="status-label state-tag ' + cls + '">' + label + '</span></div>' +
      '<div class="dates-col"><div class="dates"><span>予：' + dashOr(step.plan) + '</span></div>' +
      '<div class="dates"><span>実：' + esc(actual) + ' ' + esc(StaffStore.nameOf(step.owner || '')) + '</span></div></div></div>';
  }

  function overall(steps) {
    var applicable = steps.filter(function (s) { return !s.na; });
    if (applicable.length === 0) return '<span class="na-text">' + StepStatusStore.nameOf('NA') + '</span>';
    var late = applicable.some(isDelayed);
    var all = applicable.length > 0 && applicable.every(function (s) { return s.status === 'DONE'; });
    var any = applicable.some(function (s) { return s.status === 'DONE' || s.status === 'PROGRESS'; });
    var key = late ? 'DELAY' : (all ? 'DONE' : (any ? 'PROGRESS' : 'WAIT'));
    var label = TaskProgressStore.nameOf(key);
    var color = TaskProgressStore.colorOf(key);
    return '<span class="status-label state-tag ' + color + '">' + label + '</span>';
  }

  var classes = ClassStore.load().filter(function (c) { return c.status !== OperatingStatusStore.nameOf('STOPPED'); });
  var progressAll = ProgressStore.load();
  var tasks = TaskStore.load();
  var byName = {};
  tasks.forEach(function (t) { byName[t.name] = t; });

  var headRow = document.querySelector('#scrollArea thead tr');
  var stickyHeads = headRow.querySelectorAll('th.sticky');
  var lastSticky = stickyHeads[stickyHeads.length - 1];
  while (lastSticky.nextElementSibling) headRow.removeChild(lastSticky.nextElementSibling);
  SORTED.forEach(function (t, i) {
    if (t.status === OperatingStatusStore.nameOf('STOPPED')) return;
    var th = document.createElement('th');
    th.style.minWidth = '230px';
    th.setAttribute('data-step', i);
    th.setAttribute('data-tone', WorkTypeStore.colorOf(t.workType) || '');
    th.classList.add('no-sort');
    th.setAttribute('data-kinds', t.kinds.join(','));
    th.setAttribute('data-company', t.company || '');
    th.innerHTML = '<div class="kind-line"><span class="tag task-type-tag ' + TaskTypeStore.colorOf(t.kinds[0]) + '">' + esc(TaskTypeStore.nameOf(t.kinds[0])) + '</span></div>' +
      '<div>' + esc(DISPLAY_NO[i] + '：' + t.name) + '</div>' +
      '<div>' + esc(StaffVenderStore.nameOf(t.company)) + '</div>';
    headRow.appendChild(th);
  });
  var operationTh = document.createElement('th');
  operationTh.textContent = '操作';
  operationTh.className = 'col-actions';
  headRow.appendChild(operationTh);
  var kindsList = STEP_NAMES.map(function (name) { return byName[name] ? byName[name].kinds.join(',') : ''; });
  var body = document.getElementById('tbody');
  var delayClasses = 0;

  classes.forEach(function (c) {
    var saved = progressAll[c.id] || {};
    var start = new Date(c.start);
    var steps = STEP_NAMES.map(function (name, i) {
      var no = i + 1;
      var sv = saved[no] || {};
      var task = byName[name];
      return {
        plan: sv.plan !== undefined ? sv.plan : (task ? addDays(start, task.days) : ''),
        actual: sv.actual !== undefined ? sv.actual : '',
        owner: sv.owner !== undefined ? sv.owner : '',
        status: sv.status !== undefined ? sv.status : 'WAIT',
        memo: sv.memo !== undefined ? sv.memo : '',
        kindNa: !!(task && task.kinds.indexOf(c.taskType) === -1),
        na: (task && task.kinds.indexOf(c.taskType) === -1) || (sv.na !== undefined ? sv.na : false)
      };
    });
    var activeSteps = steps.filter(function (s, i) { return isActive(i); });
    if (activeSteps.some(isDelayed)) delayClasses++;
    var course = ClassStore.COURSES[c.courseCode];
    var related = c.related && c.related.length ? c.related.slice().sort(function (a, b) { return String(a).localeCompare(String(b), 'ja', { numeric: true }); }).join(', ') : '-';

    var owners = steps.filter(function (s, i) { return isActive(i) && !s.na && s.owner; })
      .map(function (s) { return StaffStore.nameOf(s.owner); })
      .filter(function (n, i, a) { return n && a.indexOf(n) === i; });
    var tr = document.createElement('tr');
    tr.setAttribute('data-id', c.id);
    var html = '';
    var ps = ClassStore.practiceStatus(c);
    html += '<td class="sticky col-practice">' + (ps ? '<span class="tag practice-status-tag ' + ClassStore.PRACTICE_CLASS[ps] + '">' + ps + '</span>' : '') + '</td>';
    var pj = ProjectStore.map()[c.projectCode] || {};
    html += '<td class="sticky col-customer">' + esc(pj.customer ? CustomerStore.nameOf(pj.customer) : '-') + '</td>';
    html += '<td class="sticky col-year">' + esc(yearLabel(c.year)) + '</td>';
    html += '<td class="sticky"><div>' + esc(course ? course.name : c.courseCode) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(c.courseCode) + '</div></td>';
    html += '<td class="sticky"><div>' + esc(c.lessonNo) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(related) + '</div></td>';
    html += '<td class="sticky">' + esc(c.start) + '</td>';
    html += '<td class="sticky">' + esc(c.end) + '</td>';
    html += '<td class="sticky col-manager">' + (c.managers || []).map(function (m) { return esc(StaffStore.nameOf(m)); }).join('<br>') + '</td>';
    html += '<td class="sticky">' + (c.taskType ? '<span class="tag task-type-tag ' + TaskTypeStore.colorOf(c.taskType) + '">' + esc(TaskTypeStore.nameOf(c.taskType)) + '</span>' : '') + '</td>';
    html += '<td class="sticky col-overall">' + overall(activeSteps) + '</td>';
    steps.forEach(function (s, i) {
      if (!isActive(i)) return;
      var classes = [];
      if (s.kindNa) classes.push('is-kind-na');
      if (isDelayed(s)) classes.push('is-delay');
      if (s.memo) classes.push('has-memo');
      var attrs = (classes.length ? ' class="' + classes.join(' ') + '"' : '') + (s.memo ? ' title="' + esc(s.memo) + '"' : '');
      html += '<td data-step="' + i + '" data-kinds="' + kindsList[i] + '"' + (s.kindNa ? ' data-na="1"' : '') + attrs + '>' + chip(s) + '</td>';
    });
    html += '<td class="row-actions"><a class="search-btn" href="class_progress_modify.html?id=' + encodeURIComponent(c.id) + '">更新</a></td>';
    tr.innerHTML = html;
    tr.setAttribute('data-owners', owners.join('|'));
    body.appendChild(tr);
  });

  function staffOptionsOf(affiliations, jobType) {
    return ['すべて'].concat(StaffStore.candidates({
      includeStopped: true, affiliations: affiliations, roles: ['クラス'], jobTypes: [jobType]
    })).join(',');
  }
  function applyOptions() {
    var ownerSelect = document.querySelector('.filter-panel .js-select[data-match-attr="data-owners"]');
    if (ownerSelect) ownerSelect.setAttribute('data-options', staffOptionsOf([AffiliationStore.nameOf('INTERNAL'), AffiliationStore.nameOf('PARTNER')], '実施'));
    var managerSelect = document.getElementById('managerFilter');
    if (managerSelect) managerSelect.setAttribute('data-options', staffOptionsOf(null, '管理'));
    var customerSelect = document.getElementById('customerFilter');
    if (customerSelect) customerSelect.setAttribute('data-options', ['すべて'].concat(CustomerStore.names()).join(','));
    var companyFilter = document.getElementById('companyFilter');
    if (companyFilter) {
      companyFilter.setAttribute('data-options', ['すべて', StaffVenderStore.nameOf(StaffVenderStore.INTERNAL)].concat(StaffVenderStore.load().map(function (v) { return v.name; })).join(','));
    }
  }
  applyOptions();
  document.getElementById('progressCount').textContent = classes.length;
  document.getElementById('delayCount').textContent = delayClasses;

  if (location.search.indexOf('scrolled=1') !== -1) {
    document.getElementById('scrollArea').scrollLeft = 1316;
  }
  var listTable = document.querySelector('#scrollArea table');
  listTable.style.width = 'auto';
  var stepKindCode = '';
  var stepCompanyCode = '';
  function refreshStepColumns() {
    var hiddenSteps = {};
    document.querySelectorAll('#scrollArea thead th[data-step]').forEach(function (th) {
      var kinds = (th.getAttribute('data-kinds') || '').split(',');
      var kindOk = !stepKindCode || kinds.indexOf(stepKindCode) !== -1;
      var companyOk = !stepCompanyCode || th.getAttribute('data-company') === stepCompanyCode;
      hiddenSteps[th.getAttribute('data-step')] = !(kindOk && companyOk);
    });
    document.querySelectorAll('#scrollArea [data-step]').forEach(function (el) {
      el.style.display = hiddenSteps[el.getAttribute('data-step')] ? 'none' : '';
    });
    document.querySelector('#scrollArea table').classList.toggle('hide-kind', !!stepKindCode);
    if (listTable.style.tableLayout !== 'fixed') return;
    var total = 0;
    listTable.querySelectorAll('thead th').forEach(function (th) { if (th.style.display !== 'none') total += parseFloat(th.style.width) || th.getBoundingClientRect().width; });
    listTable.style.width = total + 'px';
  }
  window.applyStepColumns = function (code) {
    stepKindCode = code || '';
    refreshStepColumns();
  };
  function applyCompanyFilter() {
    var el = document.getElementById('companyFilter');
    var name = el ? ownText(el) : '';
    stepCompanyCode = (!name || name === 'すべて') ? '' : StaffVenderStore.codeOf(name);
    refreshStepColumns();
  }
  document.addEventListener('click', function () { setTimeout(applyCompanyFilter, 0); }, true);
  applyCompanyFilter();
  window.applyColumnFilters();
  var STATUS_OF_LABEL = StepStatusStore.byName();
  var LABEL_OF_STATUS = StepStatusStore.nameByCode();
  var STATUS_COLOR_OF = { DONE: 'green', PROGRESS: 'blue', WAIT: 'gray' };
  function stepOwnerNames(task) {
    var company = task ? task.company : StaffVenderStore.INTERNAL;
    return StaffStore.load().filter(function (s) {
      if (s.status === OperatingStatusStore.nameOf('STOPPED')) return false;
      if (!(s.roles || []).some(function (code) { return StaffRoleStore.nameOf(code) === 'クラス'; })) return false;
      if (!(s.jobTypes || []).some(function (c) { return JobTypeStore.nameOf(c) === '実施'; })) return false;
      if (company === StaffVenderStore.INTERNAL) return s.affiliation === AffiliationStore.nameOf('INTERNAL');
      return s.affiliation === AffiliationStore.nameOf('PARTNER') && s.company === company;
    }).map(function (s) { return s.name; });
  }
  function valueOf(el) {
    var v = el.getAttribute('data-value');
    if (v === null || v === '') v = ownText(el);
    v = String(v || '').trim();
    return v === '選択してください' ? '' : v;
  }
  function openStepDialog(classId, i) {
    var all = ProgressStore.load();
    var sv = (all[classId] || {})[i + 1] || {};
    var cls = ClassStore.load().filter(function (c) { return c.id === classId; })[0] || {};
    var course = ClassStore.COURSES[cls.courseCode] || {};
    var classInfo = (course.name || cls.courseCode || '') + '　' + (cls.lessonNo || '') + '　' + (cls.start || '') + '〜' + (cls.end || '');
    var task = SORTED[i];
    var ownerName = StaffStore.nameOf(sv.owner || '');
    var owners = stepOwnerNames(task);
    var companyName = task ? StaffVenderStore.nameOf(task.company) : '';
    var kindTags = task ? task.kinds.map(function (k) { return '<span class="tag task-type-tag ' + TaskTypeStore.colorOf(k) + '">' + esc(TaskTypeStore.nameOf(k)) + '</span>'; }).join('') : '';
    if (ownerName && owners.indexOf(ownerName) === -1) owners.unshift(ownerName);
    var overlay = document.createElement('div');
    overlay.className = 'overlay';
    overlay.innerHTML = '<div class="input-dialog step-dialog">' +
      '<div class="input-dialog-title">' + esc(DISPLAY_NO[i] + '：' + task.name) + '</div>' +
      '<label class="input-dialog-label">クラス情報</label>' +
      '<div class="step-dialog-info">' + esc(classInfo) + '</div>' +
      '<div class="step-dialog-row">' +
        '<div class="step-dialog-cell"><label class="input-dialog-label">タスク区分</label><div class="step-dialog-value">' + kindTags + '</div></div>' +
        '<div class="step-dialog-cell"><label class="input-dialog-label">実施担当会社</label><div class="step-dialog-value">' + esc(companyName) + '</div></div>' +
      '</div>' +
      '<label class="input-dialog-label">実施</label>' +
      '<div class="radio-group" id="sdTarget">' +
        '<label class="radio-option"><input type="radio" name="sdTargetRadio" value="あり"' + (sv.na ? '' : ' checked') + '><span class="radio-dot"></span><span class="tag blue">あり</span></label>' +
        '<label class="radio-option"><input type="radio" name="sdTargetRadio" value="なし"' + (sv.na ? ' checked' : '') + '><span class="radio-dot"></span><span class="tag gray">なし</span></label>' +
      '</div>' +
      '<label class="input-dialog-label">予定日</label>' +
      '<div class="form-control js-date" id="sdPlan">' + esc(sv.plan || '') + '<span class="caret">▾</span></div>' +
      '<label class="input-dialog-label">実施日</label>' +
      '<div class="form-control js-date" id="sdActual">' + esc(sv.actual || '') + '<span class="caret">▾</span></div>' +
      '<label class="input-dialog-label">実施担当者</label>' +
      '<div class="form-control js-select" id="sdOwner" data-options="' + esc(owners.join(',')) + '">' + esc(ownerName || '選択してください') + '<span class="caret">▾</span></div>' +
      '<label class="input-dialog-label">進捗</label>' +
      '<div class="status-select status-combo ' + STATUS_COLOR_OF[sv.status || 'WAIT'] + ' js-select" id="sdStatus" data-options="' + StepStatusStore.options() + '" data-class-map=\'' + StepStatusStore.classMapJson() + '\' data-value="' + esc(LABEL_OF_STATUS[sv.status || 'WAIT']) + '">' + esc(LABEL_OF_STATUS[sv.status || 'WAIT']) + '<span class="caret">▾</span></div>' +
      '<label class="input-dialog-label">備考</label>' +
      '<textarea class="form-control textarea" id="sdMemo" rows="2">' + esc(sv.memo || '') + '</textarea>' +
      '<div class="input-dialog-actions"><div class="search-btn sd-cancel">キャンセル</div><div class="btn primary sd-ok">保存</div></div></div>';
    document.body.appendChild(overlay);
    function applyNa(off) {
      ['#sdPlan', '#sdActual', '#sdOwner', '#sdStatus'].forEach(function (sel) {
        var el = overlay.querySelector(sel);
        el.style.pointerEvents = off ? 'none' : '';
        el.style.opacity = off ? '0.4' : '';
      });
    }
    applyNa(!!sv.na);
    Array.prototype.forEach.call(overlay.querySelectorAll('input[name="sdTargetRadio"]'), function (r) {
      r.addEventListener('change', function () { applyNa(r.value === 'なし'); });
    });
    bindFormControls(overlay);
    function close() { overlay.remove(); }
    overlay.querySelector('.sd-cancel').addEventListener('click', close);
    overlay.addEventListener('click', function (e) { if (e.target === overlay) close(); });
    overlay.querySelector('.sd-ok').addEventListener('click', function () {
      var s = ProgressStore.load();
      var cur = s[classId] || {};
      var picked = valueOf(overlay.querySelector('#sdOwner'));
      cur[i + 1] = Object.assign({}, cur[i + 1] || {}, {
        status: STATUS_OF_LABEL[valueOf(overlay.querySelector('#sdStatus'))] || 'WAIT',
        plan: ownText(overlay.querySelector('#sdPlan')),
        actual: ownText(overlay.querySelector('#sdActual')),
        owner: picked ? StaffStore.codeOf(picked) : '',
        memo: overlay.querySelector('#sdMemo').value,
        na: (overlay.querySelector('input[name="sdTargetRadio"]:checked') || { value: 'あり' }).value === 'なし'
      });
      s[classId] = cur;
      ProgressStore.save(s);
      location.reload();
    });
  }
  body.addEventListener('click', function (e) {
    var td = e.target.closest('td[data-step]');
    if (!td) return;
    if (td.getAttribute('data-na')) return;
    openStepDialog(td.parentNode.getAttribute('data-id'), Number(td.getAttribute('data-step')));
  });
  window.addEventListener('storage', function (e) {
    if (e.key === 'classProgress') location.reload();
  });
})();
