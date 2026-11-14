(function () {
  var KEY = 'motivationCompanyTypeList';
  var PREFIX = 'MC-';

  var SEED = [
    { code: 'MC-01', name: '社内', color: 'blue' },
    { code: 'MC-02', name: '顧客先', color: 'orange' }
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

  window.MotivationCompanyTypeStore = { load: load, save: save, find: find, nameOf: nameOf, colorOf: colorOf, codes: codes, PREFIX: PREFIX };
})();
