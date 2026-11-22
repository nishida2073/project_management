(function () {

  function stateLabel(s) {
    return '<span class="status-label state-tag ' + s.color + '">' + esc(s.name) + '</span>';
  }

  var C = ClassStore.COURSES;
  var body = document.getElementById('venderBody');
  var list = ClassStore.load().filter(function (r) { return r.status !== OperatingStatusStore.nameOf('STOPPED'); });

  var rowLines = {};
  list.forEach(function (r) {
    var c = C[r.courseCode] || { name: r.courseCode };
    var a = VenderAssignStore.find(r.id);
    var S = VenderAssignStore.STATUS;
    var built = VenderLines.build(r);
    rowLines[r.id] = built;
    var mainLines = built.main;
    var subLines = built.sub;
    var specialLines = built.special;
    var reqs = VenderAssignStore.requestsOf(a);
    var related = r.related && r.related.length ? r.related.slice().sort(function (a, b) { return String(a).localeCompare(String(b), 'ja', { numeric: true }); }).join(', ') : '-';
    var ps = ClassStore.practiceStatus(r);
    var tr = document.createElement('tr');
    tr.setAttribute('data-id', r.id);
    var custCode = (ClassStore.PROJECTS[r.projectCode] || {}).customer;
    tr.innerHTML =
      '<td class="sticky col-practice">' + (ps ? '<span class="tag practice-status-tag ' + ClassStore.PRACTICE_CLASS[ps] + '">' + ps + '</span>' : '') + '</td>' +
      '<td class="sticky">' + esc(custCode ? CustomerStore.nameOf(custCode) : '-') + '</td>' +
      '<td class="sticky">' + esc(yearLabel(r.year)) + '</td>' +
      '<td class="sticky"><div>' + esc(c.name) + '</div><div class="vender-assign-sub">' + esc(r.courseCode) + '</div></td>' +
      '<td class="sticky"><div>' + esc(r.lessonNo) + '</div><div class="vender-assign-sub">' + esc(related) + '</div></td>' +
      '<td class="sticky">' + esc(r.start) + '</td>' +
      '<td class="sticky">' + esc(r.end) + '</td>' +
      '<td>' + dashOr(classDays(r), '日') + '</td>' +
      '<td>' + dashOr(r.mainTeachers, '人') + '</td>' +
      '<td>' + mainLines + '</td>' +
      '<td>' + dashOr(r.subTeachers, '人') + '</td>' +
      '<td>' + subLines + '</td>' +
      '<td>' + dashOr(r.specialTeachers, '人') + '</td>' +
      '<td>' + specialLines + '</td>' +
      '<td>' + (a.attendeeVendor || a.attendee ? '<div>' + dashOr(a.attendeeVendor) + '：' + dashOr(a.attendee) + '</div>' : '-') + '</td>' +
      '<td>' + (a.motivationVendor || a.motivationName ? '<div>' + esc(MotivationCompanyTypeStore.nameOf(a.motivationVendor) || '-') + '：' + dashOr(a.motivationName) + '</div>' : '-') + '</td>' +
      '<td>' + dashOr(a.contractMain) + '</td>' +
      '<td>' + dashOr(a.contractSub) + '</td>' +
      '<td>' + dashOr(a.docNo) + '</td>' +
      '<td class="memo-cell"' + (a.memo ? ' data-memo="' + esc(a.memo) + '"' : '') + '>' + (a.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="nav-btn" href="vender_assign_modify.html?id=' + encodeURIComponent(r.id) + '">更新</a></td>';
    var names = a.mains.concat(a.subs, a.specials || [], reqs).map(function (x) { return TeacherVenderStore.nameOf(x.vendor) || ''; }).filter(function (n, k, arr) { return n && arr.indexOf(n) === k; });
    tr.setAttribute('data-vendors', names.join('|'));
    body.appendChild(tr);
  });

  function applyOptions() {
    document.getElementById('vendorFilter').setAttribute('data-options', ['すべて'].concat(TeacherVenderStore.activeNames()).join(','));
  }
  applyOptions();
  document.getElementById('venderCount').textContent = list.length;
  window.addEventListener('load', function () {
    var btn = document.querySelector('.filter-panel .nav-btn');
    if (btn) btn.click();
  });
  document.querySelector('.filter-panel .nav-btn').addEventListener('click', function () { setTimeout(applyVendorLines, 0); });
  document.getElementById('importLink').addEventListener('click', function () { sessionStorage.removeItem('venderImportPlan'); });
  function applyVendorLines() {
    var name = ownText(document.getElementById('vendorFilter'));
    var code = name && name !== 'すべて' ? TeacherVenderStore.codeOf(name) : '';
    Array.prototype.forEach.call(body.querySelectorAll('[data-vendor]'), function (el) {
      el.style.display = !code || el.getAttribute('data-vendor') === code ? '' : 'none';
    });
    var table = document.querySelector('.table-scroll table');
    if (table && table.__relayout) table.__relayout();
  }

  var calView = DayTable.create({
    root: document.getElementById('calendarView'),
    isHoliday: function (k) { return HolidayStore.isHoliday(k); },
    onEventClick: function (id) { location.href = 'vender_assign_modify.html?id=' + encodeURIComponent(id); }
  });

  function pad2(n) { return n < 10 ? '0' + n : '' + n; }
  function ymd(d) { return d.getFullYear() + '/' + pad2(d.getMonth() + 1) + '/' + pad2(d.getDate()); }
  function parseYmd(str) {
    var p = String(str || '').split('/');
    if (p.length !== 3) return null;
    return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
  }

  function calData() {
    var columns = [];
    var events = {};
    var all = ClassStore.load();
    document.querySelectorAll('#venderBody tr').forEach(function (tr) {
      if (tr.style.display === 'none') return;
      var id = tr.getAttribute('data-id');
      var r = all.filter(function (x) { return String(x.id) === String(id); })[0];
      if (!r) return;
      var c = ClassStore.COURSES[r.courseCode] || { name: r.courseCode };
      var a = VenderAssignStore.find(r.id);
      var lines = ['メイン：' + rowLines[id].main, 'サブ：' + rowLines[id].sub, '特別：' + rowLines[id].special];
      var custCode = (ClassStore.PROJECTS[r.projectCode] || {}).customer;
      var tip = ['顧客：' + (custCode ? CustomerStore.nameOf(custCode) : '-'), 'コース：' + c.name, 'レッスンNo：' + (r.lessonNo || ''), '開始日：' + (r.start || ''), '終了日：' + (r.end || '')].join('\n');
      columns.push({ id: id, label: [c.name, r.lessonNo], tip: tip });
      var from = parseYmd(r.start);
      var to = parseYmd(r.end) || from;
      if (!from) return;
      for (var t = new Date(from.getFullYear(), from.getMonth(), from.getDate()); t <= to; t.setDate(t.getDate() + 1)) {
        var key = ymd(t);
        if (t.getDay() === 0 || t.getDay() === 6 || HolidayStore.isHoliday(key)) continue;
        (events[key] = events[key] || []).push({ colId: id, rowId: id, stepId: 0, lineHtml: lines, color: '' });
      }
    });
    return { columns: columns, events: events };
  }

  function renderCalendar() {
    calView.update(calData());
  }

  DayTable.bindView({
    tabs: document.getElementById('viewTabs'),
    table: document.querySelector('.table-scroll'),
    calendar: document.getElementById('calendarView'),
    render: renderCalendar,
    storageKey: 'displaySetting:view:' + location.pathname
  });
})();
