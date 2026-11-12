(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  var SORTED = TaskStore.load().slice().sort(function (a, b) {
    var ka = a.kinds[0] || '';
    var kb = b.kinds[0] || '';
    if (ka !== kb) return ka < kb ? -1 : 1;
    return a.order - b.order;
  });
  var STEP_NAMES = SORTED.map(function (t) { return t.name; });
  var STATUS_LABEL = { done: '完了', progress: '実施中', wait: '実施前' };
  var STATUS_CLASS = { done: 'green', progress: 'blue', wait: 'gray' };

  var today = new Date();
  today.setHours(0, 0, 0, 0);

  function addDays(base, days) {
    var d = new Date(base);
    d.setDate(d.getDate() + days);
    return d.getFullYear() + '/' + String(d.getMonth() + 1).padStart(2, '0') + '/' + String(d.getDate()).padStart(2, '0');
  }

  function isDelayed(step) {
    if (step.na) return false;
    if (step.status === 'done' || !step.plan) return false;
    var plan = new Date(String(step.plan).replace(/\//g, '-'));
    return !isNaN(plan.getTime()) && plan < today;
  }

  function chip(step) {
    if (step.na) return '<div class="status-chip status-chip-h"><span class="na-text">対象外</span></div>';
    var label = STATUS_LABEL[step.status] || '実施前';
    var cls = STATUS_CLASS[step.status] || 'gray';
    var actual = step.actual ? step.actual : '-';
    var delayMark = isDelayed(step) ? '<span class="badge red">⚠ 遅延</span>' : '';
    return '<div class="status-chip status-chip-h"><div class="badge-row"><span class="badge ' + cls + '">' + label + '</span>' + delayMark + '</div>' +
      '<div class="dates-col"><div class="dates"><span>予定日 ' + esc(step.plan || '-') + '</span></div>' +
      '<div class="dates"><span>実施日 ' + esc(actual) + ' ' + esc(StaffStore.nameOf(step.owner || '')) + '</span></div></div></div>';
  }

  function overall(steps) {
    var applicable = steps.filter(function (s) { return !s.na; });
    if (applicable.length === 0) return '<span class="na-text">対象外</span>';
    var late = applicable.some(isDelayed);
    var all = applicable.length > 0 && applicable.every(function (s) { return s.status === 'done'; });
    var any = applicable.some(function (s) { return s.status === 'done' || s.status === 'progress'; });
    var key = late ? 'delay' : (all ? 'done' : (any ? 'progress' : 'wait'));
    var label = { done: '完了', progress: '実施中', wait: '実施前', delay: '遅延あり' }[key];
    var color = { done: 'green', progress: 'blue', wait: 'gray', delay: 'red' }[key];
    return '<span class="overall ' + color + '">' + label + '</span>';
  }

  var classes = ClassStore.load();
  var progressAll = ProgressStore.load();
  var tasks = TaskStore.load();
  var byName = {};
  tasks.forEach(function (t) { byName[t.name] = t; });

  var headRow = document.querySelector('#scrollArea thead tr');
  while (headRow.children.length > 8) headRow.removeChild(headRow.lastElementChild);
  SORTED.forEach(function (t, i) {
    var th = document.createElement('th');
    th.style.minWidth = '170px';
    th.setAttribute('data-step', i);
    th.setAttribute('data-kinds', t.kinds.join(','));
    th.innerHTML = '<span class="tag ' + TaskTypeStore.colorOf(t.kinds[0]) + '">' + esc(TaskTypeStore.nameOf(t.kinds[0])) + '</span> ' +
      esc(t.order + ' ' + t.name) + '<div class="col-company">' + esc(StaffVenderStore.nameOf(t.company)) + '</div>';
    headRow.appendChild(th);
  });
  var operationTh = document.createElement('th');
  operationTh.textContent = '操作';
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
        status: sv.status !== undefined ? sv.status : 'wait',
        na: (task && task.kinds.indexOf(c.taskType) === -1) || (sv.na !== undefined ? sv.na : false)
      };
    });
    if (steps.some(isDelayed)) delayClasses++;
    var course = ClassStore.COURSES[c.courseCode];
    var related = c.related && c.related.length ? c.related.join(', ') : '-';

    var tr = document.createElement('tr');
    var html = '';
    html += '<td class="sticky" style="left:0;">' + esc(c.year) + '</td>';
    html += '<td class="sticky" style="left:90px;"><div>' + esc(course ? course.name : c.courseCode) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(c.courseCode) + '</div></td>';
    html += '<td class="sticky" style="left:280px;"><div>' + esc(c.lessonNo) + '</div><div style="font-size:11px;color:#9aa4b5;">' + esc(related) + '</div></td>';
    html += '<td class="sticky" style="left:410px;">' + esc(c.start) + '</td>';
    html += '<td class="sticky" style="left:530px;">' + esc(c.end) + '</td>';
    html += '<td class="sticky" style="left:650px;">' + esc(StaffStore.nameOf(c.manager)) + '</td>';
    html += '<td class="sticky" style="left:760px;">' + (c.taskType ? '<span class="tag ' + TaskTypeStore.colorOf(c.taskType) + '">' + esc(TaskTypeStore.nameOf(c.taskType)) + '</span>' : '') + '</td>';
    html += '<td class="sticky shadow" style="left:870px;">' + overall(steps) + '</td>';
    steps.forEach(function (s, i) { html += '<td data-step="' + i + '" data-kinds="' + kindsList[i] + '">' + chip(s) + '</td>'; });
    html += '<td><a class="search-btn" href="class_progress_modify.html?id=' + encodeURIComponent(c.id) + '">編集</a></td>';
    tr.innerHTML = html;
    body.appendChild(tr);
  });

  document.getElementById('progressCount').textContent = classes.length;
  document.getElementById('delayCount').textContent = delayClasses;

  if (location.search.indexOf('scrolled=1') !== -1) {
    document.getElementById('scrollArea').scrollLeft = 1316;
  }
  var listTable = document.querySelector('#scrollArea table');
  listTable.style.width = 'auto';
  window.applyStepColumns = function (code) {
    document.querySelectorAll('#scrollArea [data-step]').forEach(function (el) {
      var kinds = (el.getAttribute('data-kinds') || '').split(',');
      el.style.display = (!code || kinds.indexOf(code) !== -1) ? '' : 'none';
    });
  };
})();
