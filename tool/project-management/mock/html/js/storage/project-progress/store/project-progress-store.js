(function () {
  var KEY = 'projectProgressList';
  var STEP_KEY = 'projectProgressStepList';
  var STEP_SEED = [
    '案件受付', '見積作成', '見積提出', '受注確定', '社内承認', '教材準備', '講師手配',
    '顧客契約締結', '開発実施準備', '研修実施', 'アンケート集計', '検収', '請求・完了報告'
  ];

  function loadSteps() {
    try {
      var raw = localStorage.getItem(STEP_KEY);
      if (raw) return JSON.parse(raw);
    } catch (e) {}
    var seed = STEP_SEED.slice();
    try { localStorage.setItem(STEP_KEY, JSON.stringify(seed)); } catch (e) {}
    return seed;
  }

  var STEP_NAMES = loadSteps();

  var DATES = ['08/10', '08/20', '08/25', '08/29', '09/03', '09/08', '09/10', '09/17', '09/24', '10/05', '10/20', '11/10', '11/25'];

  function step(status, na, plan, actual, memo) {
    return { status: status, na: !!na, plan: plan, actual: actual || '', memo: memo || '' };
  }

  function build(codes) {
    return codes.map(function (s, i) {
      var na = s === 'na';
      var status = (s === 'na') ? 'wait' : (s === 'wait-delay' ? 'wait' : s);
      var plan = '2026/' + DATES[i];
      var actual = status === 'done' ? plan : '';
      return step(status, na, plan, actual, '');
    });
  }

  var SEED_STEPS = {
    'PJ-2601': build(['done', 'na', 'na', 'done', 'na', 'done', 'done', 'progress', 'wait', 'wait', 'wait', 'wait', 'wait']),
    'PJ-2602': build(['done', 'wait-delay', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait']),
    'PJ-2603': build(['done', 'done', 'progress', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait']),
    'PJ-2604': build(['done', 'done', 'done', 'na', 'na', 'done', 'na', 'done', 'done', 'done', 'done', 'progress', 'wait']),
    'PJ-2605': build(['wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait']),
    'PJ-2606': build(['done', 'done', 'done', 'done', 'wait-delay', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait']),
    'PJ-2607': build(['done', 'progress', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait'])
  };

  SEED_STEPS['PJ-2601'][7] = step('progress', false, '2026/03/11', '', '契約書ドラフト送付済み、押印待ち');
  SEED_STEPS['PJ-2601'][8] = step('wait', false, '2026/03/20', '', '契約締結後に着手予定');

  var SEED = Object.keys(SEED_STEPS).map(function (code) {
    return { projectCode: code, steps: SEED_STEPS[code] };
  });

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

  function blank(projectCode) {
    return {
      projectCode: projectCode,
      steps: STEP_NAMES.map(function () { return step('wait', false, '', '', ''); })
    };
  }

  function find(projectCode) {
    var found = load().filter(function (p) { return p.projectCode === projectCode; })[0];
    return found || blank(projectCode);
  }

  function upsert(record) {
    var list = load().filter(function (p) { return p.projectCode !== record.projectCode; });
    list.push(record);
    save(list);
  }

  window.ProjectProgressStore = { load: load, save: save, find: find, upsert: upsert, blank: blank, STEP_NAMES: STEP_NAMES };
})();
