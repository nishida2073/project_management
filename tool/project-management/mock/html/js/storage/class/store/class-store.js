(function () {
  var KEY = 'classList';

  function rec(id, year, projectCode, courseCode, lessonNo, related, start, end, delivery, people, manager, locationType, locationName) {
    return {
      id: id, year: year, version: '1.0', projectCode: projectCode, courseYear: '2026年度', courseCode: courseCode,
      lessonNo: lessonNo, related: related, start: start, end: end, delivery: delivery,
      people: people, manager: manager, locationType: locationType, locationName: locationName, memo: ''
    };
  }

  var SEED = [
    rec('CLS-001', '2026年度', 'PJ-2602', 'BC02B', '001', ['002', '003'], '2026/09/02', '2026/09/04', 'DL-01', '24', 'STF-045', 'LT-01', 'LOC-001'),
    rec('CLS-002', '2026年度', 'PJ-2602', 'BC02B', '002', ['001', '003'], '2026/09/02', '2026/09/04', 'DL-02', '20', 'STF-068', 'LT-01', 'LOC-002'),
    rec('CLS-003', '2026年度', 'PJ-2604', 'BC07A', '001', ['002'], '2026/09/08', '2026/09/09', 'DL-02', '18', 'STF-068', 'LT-01', 'LOC-002'),
    rec('CLS-004', '2026年度', 'PJ-2603', 'ND02B', '001', [], '2026/09/10', '2026/09/12', 'DL-01', '30', 'STF-065', 'LT-02', 'LOC-003'),
    rec('CLS-005', '2026年度', 'PJ-2602', 'BC02B', '003', ['001', '002'], '2026/09/15', '2026/09/17', 'DL-03', '22', 'STF-045', 'LT-01', 'LOC-001'),
    rec('CLS-006', '2026年度', 'PJ-2604', 'BC07A', '002', ['001'], '2026/09/18', '2026/09/18', 'DL-02', '40', 'STF-066', 'LT-03', 'LOC-004'),
    rec('CLS-007', '2026年度', 'PJ-2603', 'ND02B', '002', ['001', '003'], '2026/09/24', '2026/09/26', 'DL-01', '28', 'STF-065', 'LT-02', 'LOC-003'),
    rec('CLS-008', '2026年度', 'PJ-2605', 'CE01B', '001', [], '2026/09/28', '2026/09/29', 'DL-01', '20', 'STF-067', 'LT-01', 'LOC-002'),
    rec('CLS-009', '2026年度', 'PJ-2603', 'ND02B', '003', ['001', '002'], '2026/09/30', '2026/10/02', 'DL-01', '25', 'STF-065', 'LT-01', ''),
    rec('CLS-010', '2026年度', 'PJ-2605', 'CE01B', '002', [], '2026/10/05', '2026/10/07', 'DL-01', '18', 'STF-067', 'LT-02', 'LOC-003')
  ];

  function save(list) {
    try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) {}
  }

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) return JSON.parse(raw);
    } catch (e) {}
    var seed = JSON.parse(JSON.stringify(SEED));
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

  window.ClassStore = {
    PROJECTS: ProjectStore.map(),
    COURSES: CourseStore.map(),
    LOCATIONS: LocationStore.namesByType(),
    load: load,
    save: save,
    nextId: nextId,
    nextLessonNo: nextLessonNo
  };
})();
