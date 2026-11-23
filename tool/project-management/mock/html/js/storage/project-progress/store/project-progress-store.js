(function () {
  var KEY = 'projectProgressList';
  var STEP_NAMES = ProjectProgressStepStore.names();

  var SEED_OWNERS = ['STF-021', 'STF-079', 'STF-091'];

  function step(status, na, actual, memo, owner) {
    return { status: status, na: !!na, actual: actual || '', memo: memo || '', owner: owner || '' };
  }

  function buildSeedSteps(projectCode, stepCodes, overrides) {
    var project = ProjectStore.load().filter(function (p) { return p.code === projectCode; })[0] || {};
    return stepCodes.map(function (code, i) {
      if (overrides && overrides[i]) return overrides[i];
      var na = code === 'NA';
      var status = (code === 'NA') ? 'WAIT' : (code === 'WAIT_DELAY' ? 'WAIT' : code);
      var actual = status === 'DONE' ? ProjectProgressStepStore.planOf(project.startMonth, i) : '';
      return step(status, na, actual, '', actual ? SEED_OWNERS[i % SEED_OWNERS.length] : '');
    });
  }

  var SEED = [
    { projectCode: 'PJ-2601', steps: buildSeedSteps('PJ-2601', ['DONE', 'NA', 'NA', 'DONE', 'NA', 'DONE', 'DONE', 'PROGRESS', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT'], {
      7: step('PROGRESS', false, '', '契約書ドラフト送付済み、押印待ち', ''),
      8: step('WAIT', false, '', '契約締結後に着手予定', '')
    }) },
    { projectCode: 'PJ-2602', steps: buildSeedSteps('PJ-2602', ['DONE', 'WAIT_DELAY', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT']) },
    { projectCode: 'PJ-2603', steps: buildSeedSteps('PJ-2603', ['DONE', 'DONE', 'PROGRESS', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT']) },
    { projectCode: 'PJ-2604', steps: buildSeedSteps('PJ-2604', ['DONE', 'DONE', 'DONE', 'NA', 'NA', 'DONE', 'NA', 'DONE', 'DONE', 'DONE', 'DONE', 'PROGRESS', 'WAIT']) },
    { projectCode: 'PJ-2605', steps: buildSeedSteps('PJ-2605', ['WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT']) },
    { projectCode: 'PJ-2606', steps: buildSeedSteps('PJ-2606', ['DONE', 'DONE', 'DONE', 'DONE', 'WAIT_DELAY', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT']) },
    { projectCode: 'PJ-2607', steps: buildSeedSteps('PJ-2607', ['DONE', 'PROGRESS', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT', 'WAIT']) }
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

  function withPlans(projectCode, steps) {
    var project = ProjectStore.load().filter(function (p) { return p.code === projectCode; })[0] || {};
    return steps.map(function (s, i) {
      return Object.assign({}, s, { plan: s.plan || ProjectProgressStepStore.planOf(project.startMonth, i) });
    });
  }

  function blank(projectCode) {
    return {
      projectCode: projectCode,
      steps: STEP_NAMES.map(function () { return step('WAIT', false, '', '', ''); })
    };
  }

  function find(projectCode) {
    var found = load().filter(function (p) { return p.projectCode === projectCode; })[0] || blank(projectCode);
    return { projectCode: projectCode, steps: withPlans(projectCode, found.steps) };
  }

  function upsert(record) {
    var steps = record.steps.map(function (s) {
      return Object.assign({}, s);
    });
    var list = load().filter(function (p) { return p.projectCode !== record.projectCode; });
    list.push({ projectCode: record.projectCode, steps: steps });
    save(list);
  }

  window.ProjectProgressStore = { load: load, save: save, find: find, upsert: upsert, blank: blank, STEP_NAMES: STEP_NAMES };
})();
