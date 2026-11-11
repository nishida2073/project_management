(function () {
  var KEY = 'subjectTypeList';
  var PREFIX = 'ST-';

  var SEED = [
    { code: 'ST-01', name: '新入社員研修', color: 'orange' },
    { code: 'ST-02', name: '新CDPB', color: 'blue' },
    { code: 'ST-03', name: '旧CDPB', color: 'gray' }
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
    return PREFIX + String(max + 1).padStart(2, '0');
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

  window.SubjectTypeStore = { load: load, save: save, find: find, nameOf: nameOf, colorOf: colorOf, codes: codes, add: add, remove: remove };
})();
