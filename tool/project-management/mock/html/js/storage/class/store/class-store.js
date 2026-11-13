(function () {
  var KEY = 'classList';

  function pad(n) { return String(n).padStart(2, '0'); }

  function fmt(d) {
    return d.getFullYear() + '/' + pad(d.getMonth() + 1) + '/' + pad(d.getDate());
  }

  function daysFromToday(n) {
    var d = new Date();
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() + n);
    return d;
  }

  function span(phase, dur, k) {
    var start, end;
    if (phase === 'before') {
      start = daysFromToday(7 + k * 4);
      end = daysFromToday(7 + k * 4 + dur - 1);
    } else if (phase === 'during') {
      start = daysFromToday(-1);
      end = daysFromToday(Math.max(0, dur - 2));
    } else {
      end = daysFromToday(-(7 + k * 4));
      start = daysFromToday(-(7 + k * 4) - (dur - 1));
    }
    return [fmt(start), fmt(end)];
  }

  function rec(id, year, projectCode, courseCode, lessonNo, related, sp, delivery, people, manager, locationType, locationName) {
    return {
      id: id, year: year, version: '1.0', taskType: 'TK-02', projectCode: projectCode, courseYear: '2026', courseCode: courseCode,
      lessonNo: lessonNo, related: related, start: sp[0], end: sp[1], delivery: delivery,
      people: people, manager: manager, locationType: locationType, locationName: locationName, memo: ''
    };
  }

  var SEED = [
    rec('CLS-001', '2026', 'PJ-2602', 'BC02B', '001', ['002', '003'], span('before', 3, 0), 'DL-01', '24', 'STF-045', 'LT-01', 'LOC-001'),
    rec('CLS-002', '2026', 'PJ-2602', 'BC02B', '002', ['001', '003'], span('during', 3, 0), 'DL-02', '20', 'STF-068', 'LT-01', 'LOC-002'),
    rec('CLS-003', '2026', 'PJ-2604', 'BC07A', '001', ['002'], span('after', 2, 0), 'DL-02', '18', 'STF-068', 'LT-01', 'LOC-002'),
    rec('CLS-004', '2026', 'PJ-2603', 'ND02B', '001', [], span('before', 3, 1), 'DL-01', '30', 'STF-065', 'LT-02', 'LOC-003'),
    rec('CLS-005', '2026', 'PJ-2602', 'BC02B', '003', ['001', '002'], span('after', 3, 1), 'DL-03', '22', 'STF-045', 'LT-01', 'LOC-001'),
    rec('CLS-006', '2026', 'PJ-2604', 'BC07A', '002', ['001'], span('during', 1, 0), 'DL-02', '40', 'STF-066', 'LT-03', 'LOC-004'),
    rec('CLS-007', '2026', 'PJ-2603', 'ND02B', '002', ['001', '003'], span('before', 3, 2), 'DL-01', '28', 'STF-065', 'LT-02', 'LOC-003'),
    rec('CLS-008', '2026', 'PJ-2605', 'CE01B', '001', [], span('after', 2, 2), 'DL-01', '20', 'STF-067', 'LT-01', 'LOC-002'),
    rec('CLS-009', '2026', 'PJ-2603', 'ND02B', '003', ['001', '002'], span('during', 3, 0), 'DL-01', '25', 'STF-065', 'LT-01', ''),
    rec('CLS-010', '2026', 'PJ-2605', 'CE01B', '002', [], span('before', 3, 3), 'DL-01', '18', 'STF-067', 'LT-02', 'LOC-003')
  ];
  SEED.forEach(function (r) {
    if (['CLS-002', 'CLS-004', 'CLS-006', 'CLS-008'].indexOf(r.id) !== -1) r.taskType = 'TK-01';
  });
  var TEACHER_COUNTS = {
    'CLS-001': ['1', '1'], 'CLS-002': ['1', '0'], 'CLS-003': ['1', '1'], 'CLS-004': ['2', '0'], 'CLS-005': ['1', '2'],
    'CLS-006': ['1', '0'], 'CLS-007': ['2', '1'], 'CLS-008': ['1', '0'], 'CLS-009': ['1', '1'], 'CLS-010': ['1', '0']
  };
  SEED.forEach(function (r) {
    var t = TEACHER_COUNTS[r.id];
    if (t) { r.mainTeachers = t[0]; r.subTeachers = t[1]; }
  });

  function save(list) {
    try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) {}
  }

  function normalize(r) {
    if (!r.managers) r.managers = r.manager ? [r.manager] : [];
    delete r.manager;
    return r;
  }

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) return JSON.parse(raw).map(normalize);
    } catch (e) {}
    var seed = JSON.parse(JSON.stringify(SEED)).map(normalize);
    save(seed);
    return seed;
  }

  function nextId(list) {
    var max = 0;
    list.forEach(function (r) {
      var n = parseInt(String(r.id).replace('CLS-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'CLS-' + String(max + 1).padStart(3, '0');
  }

  function nextLessonNo(list, courseCode) {
    var max = 0;
    list.forEach(function (r) {
      if (r.courseCode !== courseCode) return;
      var n = parseInt(r.lessonNo, 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return String(max + 1).padStart(3, '0');
  }

  function toDate(s) {
    if (!s) return null;
    var d = new Date(String(s).replace(/\//g, '-'));
    return isNaN(d.getTime()) ? null : d;
  }

  function practiceStatus(r) {
    var start = toDate(r.start);
    var end = toDate(r.end);
    if (!start || !end) return '';
    var now = new Date();
    now.setHours(0, 0, 0, 0);
    if (now < start) return '実施前';
    if (now > end) return '実施後';
    return '実施中';
  }

  window.ClassStore = {
    PROJECTS: ProjectStore.map(),
    COURSES: CourseStore.map(),
    LOCATIONS: LocationStore.namesByType(),
    load: load,
    save: save,
    nextId: nextId,
    nextLessonNo: nextLessonNo,
    practiceStatus: practiceStatus,
    PRACTICE_CLASS: { '実施前': 'blue', '実施中': 'orange', '実施後': 'gray' }
  };
})();
