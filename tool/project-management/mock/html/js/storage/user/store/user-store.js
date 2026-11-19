(function () {
  var KEY = 'userList_v2';

  var SEED = [
    { code: 'USR-001', name: '山田 太郎', email: 'yamada@company.co.jp', authority: 'AU-01', password: 'pass', status: OperatingStatusStore.nameOf('ACTIVE') },
    { code: 'USR-002', name: '佐藤 一郎', email: 'sato@company.co.jp', authority: 'AU-02', password: 'pass', status: OperatingStatusStore.nameOf('ACTIVE') },
    { code: 'USR-003', name: '荒牧 麻衣', email: 'aramaki@company.co.jp', authority: 'AU-02', password: 'pass', status: OperatingStatusStore.nameOf('ACTIVE') },
    { code: 'USR-004', name: '中村 桂', email: 'nakamura@company.co.jp', authority: 'AU-02', password: 'pass', status: OperatingStatusStore.nameOf('STOPPED') },
    { code: 'USR-005', name: '藤井 誠', email: 'fujii@neu-training.co.jp', authority: 'AU-02', password: 'pass', status: OperatingStatusStore.nameOf('ACTIVE') },
    { code: 'USR-006', name: '細野 恵美', email: 'hosono@company.co.jp', authority: 'AU-02', password: 'pass', status: OperatingStatusStore.nameOf('ACTIVE') },
    { code: 'USR-007', name: '村上 怜', email: 'murakami@company.co.jp', authority: 'AU-02', password: 'pass', status: OperatingStatusStore.nameOf('ACTIVE') },
    { code: 'USR-008', name: '中野 亮', email: 'nakano@neu-training.co.jp', authority: 'AU-02', password: 'pass', status: OperatingStatusStore.nameOf('ACTIVE') },
    { code: 'USR-009', name: '西村 美穂', email: 'nishimura@ndu-partners.co.jp', authority: 'AU-02', password: 'pass', status: OperatingStatusStore.nameOf('ACTIVE') },
    { code: 'USR-010', name: '清水 理恵', email: 'shimizu@company.co.jp', authority: 'AU-02', password: 'pass', status: OperatingStatusStore.nameOf('ACTIVE') },
    { code: 'USR-011', name: 'サンプル管理者', email: 'sample@co.jp', authority: 'AU-01', password: 'pass', status: OperatingStatusStore.nameOf('ACTIVE') }
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
    list.forEach(function (u) {
      var n = parseInt(String(u.code).replace('USR-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'USR-' + String(max + 1).padStart(3, '0');
  }

  window.UserStore = { load: load, save: save, nextCode: nextCode };
})();
