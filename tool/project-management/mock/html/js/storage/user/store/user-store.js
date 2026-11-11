(function () {
  var KEY = 'userList';

  var SEED = [
    { code: 'USR-001', name: '山田 太郎', email: 'yamada@company.co.jp', authority: 'AU-01', status: '稼働中' },
    { code: 'USR-002', name: '佐藤 一郎', email: 'sato@company.co.jp', authority: 'AU-02', status: '稼働中' },
    { code: 'USR-003', name: '荒牧 麻衣', email: 'aramaki@company.co.jp', authority: 'AU-02', status: '稼働中' },
    { code: 'USR-004', name: '中村 桂', email: 'nakamura@company.co.jp', authority: 'AU-02', status: '停止中' },
    { code: 'USR-005', name: '藤井 誠', email: 'fujii@neu-training.co.jp', authority: 'AU-02', status: '稼働中' }
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
