(function () {
  var KEY = 'locationList';

  var SEED = [
    { code: 'LOC-001', type: 'LT-01', name: '501教室', tel: '03-1111-2222', address: '東京都目黒区駒場4-6-1', status: '稼働中' },
    { code: 'LOC-002', type: 'LT-01', name: '601教室', tel: '03-1111-2222', address: '東京都目黒区駒場4-6-1', status: '稼働中' },
    { code: 'LOC-003', type: 'LT-02', name: '302教室', tel: '03-2222-3333', address: '東京都世田谷区成城6-1-1', status: '稼働中' },
    { code: 'LOC-004', type: 'LT-03', name: '外部貸会議室A', tel: '03-3333-4444', address: '東京都千代田区大手町1-1-1', status: '停止中' }
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
    list.forEach(function (l) {
      var n = parseInt(String(l.code).replace('LOC-', ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return 'LOC-' + String(max + 1).padStart(3, '0');
  }

  function namesByType() {
    var out = {};
    load().forEach(function (l) {
      if (l.status !== '稼働中') return;
      if (!out[l.type]) out[l.type] = [];
      out[l.type].push(l.name);
    });
    return out;
  }

  function nameOf(code) {
    var found = load().filter(function (l) { return l.code === code; })[0];
    return found ? found.name : '';
  }

  function codeOf(name) {
    var found = load().filter(function (l) { return l.name === name; })[0];
    return found ? found.code : '';
  }

  window.LocationStore = {
    nameOf: nameOf,
    codeOf: codeOf,
    load: load,
    save: save,
    nextCode: nextCode,
    namesByType: namesByType
  };
})();
