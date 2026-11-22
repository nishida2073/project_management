(function () {

  var body = document.getElementById('courseBody');
  var list = CourseStore.load();

  var today = new Date();
  today.setHours(0, 0, 0, 0);
  var endedCount = {};
  ClassStore.load().forEach(function (r) {
    var end = new Date(String(r.end).replace(/\//g, '-'));
    if (!isNaN(end.getTime()) && end < today) endedCount[r.courseCode] = (endedCount[r.courseCode] || 0) + 1;
  });

  list.forEach(function (c) {
    var planned = CourseStore.planned(c);
    var actual = endedCount[c.code] || 0;
    var on = c.status !== OperatingStatusStore.nameOf('STOPPED');
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td class="sticky">' + esc(yearLabel(c.year)) + '</td>' +
      '<td class="sticky">' + esc(c.code) + '</td>' +
      '<td class="sticky"><span class="tag participation-type-tag ' + ParticipationTypeStore.colorOf(c.part) + '">' + esc(ParticipationTypeStore.nameOf(c.part)) + '</span></td>' +
      '<td class="sticky">' + esc(c.name) + '</td>' +
      '<td class="sticky">' + (SubjectStore.find(c.subject) ? '<span class="tag subject-type-tag ' + SubjectTypeStore.colorOf(SubjectStore.find(c.subject).type) + '">' + esc(SubjectTypeStore.nameOf(SubjectStore.find(c.subject).type)) + '</span>' : '-') + '</td>' +
      '<td>' + dashOr(c.days, '日') + '</td>' +
      '<td>' + (c.duration ? TimeUtil.toTime(Number(c.duration)) : '-') + '</td>' +
      '<td>' + ((c.breakTime === undefined || c.breakTime === '') ? '-' : TimeUtil.toTime(Number(c.breakTime))) + '</td>' +
      (c.delivery ? '<td><span class="tag delivery-type-tag ' + DeliveryTypeStore.colorOf(c.delivery) + '">' + esc(DeliveryTypeStore.nameOf(c.delivery)) + '</span></td>' : '<td>-</td>') +
      '<td>' + dashOr(c.min, '人') + '</td>' +
      '<td>' + dashOr(c.max, '人') + '</td>' +
      '<td>' + dashOr(c.mainTeachers, '人') + '</td>' +
      '<td>' + dashOr(c.subTeachers, '人') + '</td>' +
      '<td>' + dashOr(c.specialTeachers, '人') + '</td>' +
      '<td>' + esc(actual) + '/' + planned + 'クラス</td>' +
      '<td><span class="status-label ' + (on ? 'green' : 'gray') + '">' + (on ? OperatingStatusStore.nameOf('ACTIVE') : OperatingStatusStore.nameOf('STOPPED')) + '</span></td>' +
      '<td class="memo-cell"' + (c.memo ? ' data-memo="' + esc(c.memo) + '"' : '') + '>' + (c.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="nav-btn" href="course_modify.html?id=' + encodeURIComponent(c.code) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('courseCount').textContent = list.length;
})();

(function () {
  function minutesOf(v) { return v ? TimeUtil.toMinutes(v) : ''; }
  function timeOf(v) { return v ? TimeUtil.toTime(Number(v)) : ''; }
  var SHEET_SPEC = {
    sheetName: 'コース',
    load: function () { return CourseStore.load(); },
    columns: [
      { key: 'code', label: 'コード', type: 'text', required: true },
      { key: 'year', label: '年度', type: 'text', required: false },
      { key: 'subject', label: '科目名', type: 'text', required: false,
        format: function (r) { return SubjectStore.nameOf(r.subject); },
        parse: function (t) { return SubjectStore.codeOf(t); } },
      { key: 'part', label: '参加区分', type: 'text', required: false,
        format: function (r) { return ParticipationTypeStore.nameOf(r.part); },
        parse: function (t) { return StoreImport.codeByName(ParticipationTypeStore, t); } },
      { key: 'name', label: '名称', type: 'text', required: true },
      { key: 'delivery', label: '実施形態', type: 'text', required: false,
        format: function (r) { return DeliveryTypeStore.nameOf(r.delivery); },
        parse: function (t) { return StoreImport.codeByName(DeliveryTypeStore, t); } },
      { key: 'days', label: '日数', type: 'text', required: false, format: function (r) { return r.days === undefined ? '' : r.days; }, parse: StoreImport.numOf },
      { key: 'duration', label: '実施時間', type: 'text', required: false, format: function (r) { return timeOf(r.duration); }, parse: minutesOf },
      { key: 'breakTime', label: '休憩時間', type: 'text', required: false, format: function (r) { return timeOf(r.breakTime); }, parse: minutesOf },
      { key: 'min', label: '最小人数', type: 'text', required: false, format: function (r) { return r.min === undefined ? '' : r.min; }, parse: StoreImport.numOf },
      { key: 'max', label: '最大人数', type: 'text', required: false, format: function (r) { return r.max === undefined ? '' : r.max; }, parse: StoreImport.numOf },
      { key: 'mainTeachers', label: '講師数（メイン）', type: 'text', required: false, format: function (r) { return r.mainTeachers === undefined ? '' : r.mainTeachers; }, parse: StoreImport.numOf },
      { key: 'subTeachers', label: '講師数（サブ）', type: 'text', required: false, format: function (r) { return r.subTeachers === undefined ? '' : r.subTeachers; }, parse: StoreImport.numOf },
      { key: 'specialTeachers', label: '講師数（特別）', type: 'text', required: false, format: function (r) { return r.specialTeachers === undefined ? '' : r.specialTeachers; }, parse: StoreImport.numOf },
      { key: 'month0', label: '4月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[0]) || 0; } },
      { key: 'month1', label: '5月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[1]) || 0; } },
      { key: 'month2', label: '6月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[2]) || 0; } },
      { key: 'month3', label: '7月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[3]) || 0; } },
      { key: 'month4', label: '8月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[4]) || 0; } },
      { key: 'month5', label: '9月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[5]) || 0; } },
      { key: 'month6', label: '10月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[6]) || 0; } },
      { key: 'month7', label: '11月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[7]) || 0; } },
      { key: 'month8', label: '12月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[8]) || 0; } },
      { key: 'month9', label: '1月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[9]) || 0; } },
      { key: 'month10', label: '2月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[10]) || 0; } },
      { key: 'month11', label: '3月', type: 'text', required: false, format: function (r) { return (r.monthly && r.monthly[11]) || 0; } },
      { key: 'memo', label: '備考', type: 'text', required: false, format: function (r) { return r.memo || ''; } },
      { key: 'status', label: '稼働状態', type: 'select', required: true, options: [OperatingStatusStore.nameOf('ACTIVE'), OperatingStatusStore.nameOf('STOPPED')] }
    ],
    existingKeys: function () { return CourseStore.load().map(function (c) { return c.code; }); },
    keyOf: function (o) { return o.code; },
    add: function (o) {
      var list = CourseStore.load();
      list.push(courseRecord(o));
      CourseStore.save(list);
    },
    update: function (o) {
      var list = CourseStore.load();
      list.forEach(function (c) {
        if (c.code === o.code) {
          var rec = courseRecord(o);
          rec.actual = c.actual;
          for (var k in rec) { c[k] = rec[k]; }
        }
      });
      CourseStore.save(list);
    },
    refresh: function () { location.reload(); }
  };
  function courseRecord(o) {
    var monthly = [];
    for (var i = 0; i < 12; i++) { monthly.push(Number(o['month' + i]) || 0); }
    return { code: o.code, year: o.year, subject: o.subject, part: o.part, name: o.name, delivery: o.delivery,
      days: o.days, duration: o.duration, breakTime: o.breakTime, min: o.min, max: o.max,
      mainTeachers: o.mainTeachers, subTeachers: o.subTeachers, specialTeachers: o.specialTeachers,
      monthly: monthly, memo: o.memo, status: o.status, actual: 0 };
  }
  StoreImport.bind(SHEET_SPEC, { export: 'courseExport', import: 'courseImport', file: 'courseImportFile', fileName: 'コース.xlsx' });
})();
