(function () {
  var KEY = 'subjectList';

  var SEED = [
    { code: 'BC02', name: 'システム開発入門', type: 'ST-01', status: '稼働中' },
    { code: 'BC07', name: '基盤技術基礎', type: 'ST-02', status: '稼働中' },
    { code: 'BC12', name: 'AP要件定義基礎', type: 'ST-02', status: '稼働中' },
    { code: 'BC17', name: 'AP設計・製造基礎', type: 'ST-02', status: '稼働中' },
    { code: 'BC22', name: 'AP試験基礎', type: 'ST-02', status: '稼働中' },
    { code: 'BC27', name: 'データモデル設計基礎', type: 'ST-02', status: '稼働中' },
    { code: 'BC32', name: '基盤構築プロセス基礎', type: 'ST-02', status: '稼働中' },
    { code: 'DP08', name: '営業基本Ⅰ', type: 'ST-03', status: '稼働中' },
    { code: 'DP16', name: '営業リスクマネジメントⅠ', type: 'ST-03', status: '稼働中' },
    { code: 'GC01', name: 'IT-PM入門', type: 'ST-02', status: '稼働中' },
    { code: 'GC06', name: '品質管理入門', type: 'ST-02', status: '稼働中' },
    { code: 'BE10', name: 'システム基盤実践', type: 'ST-02', status: '稼働中' },
    { code: 'AA60', name: 'フォローアップ研修', type: 'ST-01', status: '稼働中' },
    { code: 'BD11', name: 'システム開発基礎', type: 'ST-02', status: '稼働中' },
    { code: 'BD12', name: '基盤技術基礎（外販）', type: 'ST-02', status: '稼働中' },
    { code: 'BD13', name: '要件定義基礎', type: 'ST-02', status: '稼働中' },
    { code: 'BD14', name: 'ソフトウェア設計基礎', type: 'ST-02', status: '稼働中' },
    { code: 'BD15', name: 'データモデル設計基礎（外販）', type: 'ST-02', status: '稼働中' },
    { code: 'BD16', name: 'ソフトウェア試験基礎', type: 'ST-02', status: '稼働中' },
    { code: 'BD17', name: '品質管理基礎', type: 'ST-02', status: '稼働中' },
    { code: 'BD18', name: 'プロジェクトマネジメント基礎', type: 'ST-02', status: '稼働中' }
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

  function find(code) {
    return load().filter(function (s) { return s.code === code; })[0];
  }

  function nameOf(code) {
    var found = find(code);
    return found ? found.name : '';
  }

  function codeOf(name) {
    var found = load().filter(function (s) { return s.name === name; })[0];
    return found ? found.code : '';
  }

  function activeNames() {
    return load().filter(function (s) { return s.status !== '停止中'; }).map(function (s) { return s.name; });
  }

  function isValidCode(code) {
    return /^[A-Z]{2}\d{2}$/.test(code);
  }

  window.SubjectStore = { load: load, save: save, find: find, nameOf: nameOf, codeOf: codeOf, activeNames: activeNames, isValidCode: isValidCode };
})();
