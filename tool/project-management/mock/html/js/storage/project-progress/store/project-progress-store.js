(function () {
  var KEY = 'projectProgressList';
  var STEP_KEY = 'projectProgressStepList';

  var STEP_SEED = [
    '案件受付', '見積作成', '見積提出', '受注確定', '社内承認', '教材準備', '講師手配',
    '顧客契約締結', '開発実施準備', '研修実施', 'アンケート集計', '検収', '請求・完了報告'
  ];

  var SEED_PLAN_DATES = ['2026/08/10', '2026/08/20', '2026/08/25', '2026/08/29', '2026/09/03', '2026/09/08', '2026/09/10', '2026/09/17', '2026/09/24', '2026/10/05', '2026/10/20', '2026/11/10', '2026/11/25'];

  var OWNERS = ['STF-021', 'STF-079', 'STF-091'];

  function step(status, na, plan, actual, memo, owner) {
    return { status: status, na: !!na, plan: plan, actual: actual || '', memo: memo || '', owner: owner || '' };
  }

  function buildSeedSteps(stepCodes) {
    return stepCodes.map(function (code, i) {
      var na = code === 'NA';
      var status = (code === 'NA') ? 'WAIT' : (code === 'WAIT_DELAY' ? 'WAIT' : code);
      var plan = SEED_PLAN_DATES[i];
      var actual = status === 'DONE' ? plan : '';
      return step(status, na, plan, actual, '', na ? '' : OWNERS[i % OWNERS.length]);
    });
  }

  var SEED_STEPS = {
    'PJ-2601': buildSeedSteps(['DONE', 'NA', 'NA', 'DONE', 'NA', 'DONE', 'DONE', 'PROGRESS', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT']),
    'PJ-2602': buildSeedSteps(['DONE', 'WAIT_DELAY', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT']),
    'PJ-2603': buildSeedSteps(['DONE', 'DONE', 'PROGRESS', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT']),
    'PJ-2604': buildSeedSteps(['DONE', 'DONE', 'DONE', 'NA', 'NA', 'DONE', 'NA', 'DONE', 'DONE', 'DONE', 'DONE', 'PROGRESS', 'WAIT']),
    'PJ-2605': buildSeedSteps(['WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT']),
    'PJ-2606': buildSeedSteps(['DONE', 'DONE', 'DONE', 'DONE', 'WAIT_DELAY', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT']),
    'PJ-2607': buildSeedSteps(['DONE', 'PROGRESS', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT'])
  };

  SEED_STEPS['PJ-2601'][7] = step('PROGRESS', false, '2026/03/11', '', '契約書ドラフト送付済み、押印待ち', 'STF-021');
  SEED_STEPS['PJ-2601'][8] = step('WAIT', false, '2026/03/20', '', '契約締結後に着手予定', 'STF-079');

  var SEED = Object.keys(SEED_STEPS).map(function (code) {
    return { projectCode: code, steps: SEED_STEPS[code] };
  });

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
      steps: STEP_NAMES.map(function () { return step('WAIT', false, '', '', ''); })
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
