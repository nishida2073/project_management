(function () {
  var KEY = 'participationTypeList';
  var PREFIX = 'PT-';

  var SEED = [
    { code: 'PT-01', name: '受託', color: 'blue' },
    { code: 'PT-02', name: '公募', color: 'orange' }
  ];

  function save(list) {
    try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) {}
  }

  function byCode(a, b) {
    return String(a.code).localeCompare(String(b.code), 'en', { numeric: true });
  }

  function load() {
    return JSON.parse(JSON.stringify(SEED)).sort(byCode);
  }

  function find(code) {
    return load().filter(function (t) { return t.code === code; })[0];
  }

  function nameOf(code) {
    var found = find(code);
    return found ? found.name : '';
  }

  function colorOf(code) {
    var found = find(code);
    return found ? found.color : '';
  }

  function codes() {
    return load().map(function (t) { return t.code; });
  }

  function nextCode(list) {
    var max = 0;
    list.forEach(function (t) {
      var n = parseInt(String(t.code).replace(PREFIX, ''), 10);
      if (!isNaN(n) && n > max) max = n;
    });
    return PREFIX + pad2(max + 1);
  }

  function add(name, color) {
    var list = load();
    if (!name || list.some(function (t) { return t.name === name; })) return false;
    list.push({ code: nextCode(list), name: name, color: color || '' });
    save(list);
    return true;
  }

  function remove(code) {
    save(load().filter(function (t) { return t.code !== code; }));
  }

  window.ParticipationTypeStore = { load: load, save: save, find: find, nameOf: nameOf, colorOf: colorOf, codes: codes, add: add, remove: remove };
})();
