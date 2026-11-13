(function () {
  var KEY = 'workTypeList';
  var SEED = [
    { code: 'WT-01', name: '事前準備', color: 'blue' },
    { code: 'WT-02', name: '事後対応', color: 'green' },
    { code: 'WT-03', name: '特別対応', color: 'red' }
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

  window.WorkTypeStore = { load: load, save: save, find: find, nameOf: nameOf, colorOf: colorOf };
})();
