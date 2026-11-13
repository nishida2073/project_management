(function () {
  var KEY = 'classProgress';

  function pad2(n) { return String(n).padStart(2, '0'); }

  function fmtDate(d) {
    return d.getFullYear() + '/' + pad2(d.getMonth() + 1) + '/' + pad2(d.getDate());
  }

  function parseDate(s) {
    return new Date(String(s).replace(/\//g, '-'));
  }

  function addDays(base, days) {
    var d = new Date(base);
    d.setDate(d.getDate() + days);
    return d;
  }

  function buildSeed() {
    if (!window.ClassStore || !window.TaskStore || !window.StaffStore || !window.StaffRoleStore || !window.JobTypeStore || !window.StaffVenderStore) return {};
    var today = new Date();
    today.setHours(0, 0, 0, 0);

    var tasks = TaskStore.load().slice().sort(function (a, b) {
      var ka = a.kinds[0] || '', kb = b.kinds[0] || '';
      if (ka !== kb) return ka < kb ? -1 : 1;
      return a.order - b.order;
    });

    var pool = StaffStore.load().filter(function (s) {
      return s.status !== '停止中'
        && (s.roles || []).some(function (c) { return StaffRoleStore.nameOf(c) === 'クラス'; })
        && (s.jobTypes || []).some(function (c) { return JobTypeStore.nameOf(c) === '実施'; });
    });

    var cursor = {};
    function pickOwner(task) {
      var key = task.company || StaffVenderStore.INTERNAL;
      var list = pool.filter(function (s) {
        return task.company === StaffVenderStore.INTERNAL ? s.affiliation === '社内' : s.company === task.company;
      });
      if (!list.length) return '';
      var n = (cursor[key] = (cursor[key] || 0) + 1);
      return list[(n - 1) % list.length].code;
    }

    var out = {};
    ClassStore.load().forEach(function (c) {
      if (c.status === '停止中') return;
      var phase = ClassStore.practiceStatus(c);
      var start = parseDate(c.start);
      var saved = {};
      var j = 0;
      tasks.forEach(function (t, i) {
        if (t.status === '停止中') return;
        var no = i + 1;
        if (t.kinds.indexOf(c.taskType) === -1) { saved[no] = { na: true }; return; }
        var plan = addDays(start, t.days);
        var sv = {};
        if (phase === '実施後') {
          sv.status = 'done';
          sv.actual = fmtDate(plan > today ? today : plan);
          sv.owner = pickOwner(t);
        } else if (phase === '実施中') {
          if (plan < today && j % 2 === 0) {
            sv.status = 'done';
            sv.actual = fmtDate(plan);
            sv.owner = pickOwner(t);
          } else if (plan < today) {
            sv.status = 'progress';
          } else {
            sv.status = 'wait';
          }
        } else {
          sv.status = 'wait';
        }
        j++;
        saved[no] = sv;
      });
      out[c.id] = saved;
    });
    return out;
  }

  function load() {
    var raw;
    try { raw = localStorage.getItem(KEY); } catch (e) { return {}; }
    if (raw !== null) {
      try { return JSON.parse(raw) || {}; } catch (e) { return {}; }
    }
    var seed = buildSeed();
    save(seed);
    return seed;
  }

  function save(all) {
    try { localStorage.setItem(KEY, JSON.stringify(all)); } catch (e) {}
  }

  window.ProgressStore = { load: load, save: save };
})();
