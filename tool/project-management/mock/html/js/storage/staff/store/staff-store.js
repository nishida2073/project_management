(function () {
  var KEY = 'staffList';

  var SEED = [
    { code: 'STF-014', affiliation: '社内', company: '', name: '山口 直人', email: 'yamaguchi@company.co.jp', roles: ['SR-01'], jobType: 'JT-02', positions: ['PS-01'], status: '稼働中' },
    { code: 'STF-021', affiliation: '社内', company: '', name: '細野 恵美', email: 'hosono@company.co.jp', roles: ['SR-01'], jobType: 'JT-02', positions: ['PS-02'], status: '稼働中' },
    { code: 'STF-022', affiliation: '社内', company: '', name: '市村 拓也', email: 'ichimura@company.co.jp', roles: ['SR-01'], jobType: 'JT-02', positions: ['PS-02'], status: '稼働中' },
    { code: 'STF-033', affiliation: '社内', company: '', name: '荒牧 麻衣', email: 'aramaki@company.co.jp', roles: ['SR-01'], jobType: 'JT-01', positions: [], status: '稼働中' },
    { code: 'STF-045', affiliation: '社内', company: '', name: '佐藤 一郎', email: 'sato@company.co.jp', roles: ['SR-02'], jobType: 'JT-03', positions: [], status: '稼働中' },
    { code: 'STF-052', affiliation: '社内', company: '', name: '中村 桂', email: 'nakamura@company.co.jp', roles: ['SR-02'], jobType: 'JT-02', positions: ['PS-01'], status: '停止中' },
    { code: 'STF-060', affiliation: 'パートナー', company: 'VND-001', name: '藤井 誠', email: 'fujii@neu-training.co.jp', roles: ['SR-02'], jobType: 'JT-03', positions: [], status: '稼働中' },
    { code: 'STF-061', affiliation: 'パートナー', company: 'VND-002', name: '森 美香', email: 'mori@ndu-partners.co.jp', roles: ['SR-02'], jobType: 'JT-03', positions: [], status: '稼働中' },
    { code: 'STF-062', affiliation: 'パートナー', company: 'VND-003', name: '田村 翔', email: 'tamura@univa-service.co.jp', roles: ['SR-02'], jobType: 'JT-03', positions: [], status: '稼働中' },
    { code: 'STF-063', affiliation: 'パートナー', company: 'VND-004', name: '小野 健二', email: 'ono@cec-trust.co.jp', roles: ['SR-01'], jobType: 'JT-02', positions: ['PS-02'], status: '停止中' },
    { code: 'STF-064', affiliation: '社内', company: '', name: '田中 誠', email: '', roles: ['SR-01'], jobType: 'JT-02', positions: [], status: '稼働中' },
    { code: 'STF-065', affiliation: '社内', company: '', name: '高橋 健', email: '', roles: ['SR-01', 'SR-02'], jobType: 'JT-02', positions: [], status: '稼働中' },
    { code: 'STF-066', affiliation: '社内', company: '', name: '伊藤 美咲', email: '', roles: ['SR-01', 'SR-02'], jobType: 'JT-02', positions: [], status: '稼働中' },
    { code: 'STF-067', affiliation: '社内', company: '', name: '渡辺 直樹', email: '', roles: ['SR-01', 'SR-02'], jobType: 'JT-02', positions: [], status: '稼働中' },
    { code: 'STF-068', affiliation: '社内', company: '', name: '鈴木 花子', email: '', roles: ['SR-02'], jobType: 'JT-02', positions: [], status: '稼働中' },
    { code: 'STF-069', affiliation: '社内', company: '', name: '木村 隆', email: '', roles: ['SR-01'], jobType: 'JT-02', positions: [], status: '稼働中' },
    { code: 'STF-070', affiliation: '社内', company: '', name: '小林 由美', email: '', roles: ['SR-01'], jobType: 'JT-02', positions: [], status: '稼働中' },
    { code: 'STF-071', affiliation: '社内', company: '', name: '松本 健二', email: '', roles: ['SR-01'], jobType: 'JT-02', positions: [], status: '稼働中' },
    { code: 'STF-072', affiliation: '社内', company: '', name: '岡田 沙織', email: '', roles: ['SR-01'], jobType: 'JT-02', positions: [], status: '稼働中' },
    { code: 'STF-073', affiliation: '社内', company: '', name: '中島 拓海', email: '', roles: ['SR-01'], jobType: 'JT-02', positions: [], status: '稼働中' }
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

  function nextCode(list) {
    var max = 0;
    list.forEach(function (t) {
      var n = parseInt(String(t.code).replace('STF-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'STF-' + String(max + 1).padStart(3, '0');
  }

  function activeNames() {
    return load().filter(function (t) { return t.status !== '停止中'; }).map(function (t) { return t.name; });
  }

  var TEAM_OPS = 'OPS';
  var TEAM_OPS_NAME = '運営チーム';

  function nameOf(code) {
    if (code === TEAM_OPS) return TEAM_OPS_NAME;
    var found = load().filter(function (s) { return s.code === code; })[0];
    return found ? found.name : '';
  }

  function codeOf(name) {
    if (name === TEAM_OPS_NAME) return TEAM_OPS;
    var found = load().filter(function (s) { return s.name === name; })[0];
    return found ? found.code : '';
  }

  function optionNames() {
    return activeNames().concat([TEAM_OPS_NAME]);
  }

  window.StaffStore = { load: load, save: save, nextCode: nextCode, activeNames: activeNames, nameOf: nameOf, codeOf: codeOf, optionNames: optionNames };
})();
