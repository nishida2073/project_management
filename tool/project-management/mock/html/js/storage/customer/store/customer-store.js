(function () {
  var KEY = 'customerList';

  var SEED = [
    { id: 'CUS-001', name: 'NTTデータ金融', staff: '山口 直人' },
    { id: 'CUS-002', name: '株式会社ABC商事', staff: '荒牧 麻衣' },
    { id: 'CUS-003', name: 'DEFホールディングス', staff: '佐藤 一郎' },
    { id: 'CUS-004', name: 'CECトラスト', staff: '細野 恵美' },
    { id: 'CUS-005', name: 'NTTデータUNIV', staff: '市村 拓也' },
    { id: 'CUS-006', name: 'グループ各社', staff: '佐藤 一郎' }
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
    list.forEach(function (c) {
      var n = parseInt(String(c.id).replace('CUS-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'CUS-' + String(max + 1).padStart(3, '0');
  }

  function names() {
    return load().map(function (c) { return c.name; });
  }

  function nameOf(id) {
    var found = load().filter(function (c) { return c.id === id; })[0];
    return found ? found.name : '';
  }

  function codeOf(name) {
    var found = load().filter(function (c) { return c.name === name; })[0];
    return found ? found.id : '';
  }

  window.CustomerStore = { load: load, save: save, nextId: nextId, names: names, nameOf: nameOf, codeOf: codeOf };
})();
