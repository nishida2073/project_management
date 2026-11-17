(function () {
  var SEED = [
    { code: 'INTERNAL', name: '社内', color: 'blue' },
    { code: 'PARTNER', name: 'パートナー', color: 'orange' }
  ];

  var list = JSON.parse(JSON.stringify(SEED));

  function save(next) {
    list = JSON.parse(JSON.stringify(next));
  }

  function load() {
    return JSON.parse(JSON.stringify(list));
  }

  function find(code) {
    return load().filter(function (t) { return t.code === code; })[0];
  }

  function nameOf(code) {
    var found = find(code);
    return found ? found.name : '';
  }

  function codeOf(name) {
    var found = load().filter(function (t) { return t.name === name; })[0];
    return found ? found.code : '';
  }

  function colorOf(code) {
    var found = find(code);
    return found ? found.color : '';
  }

  function codes() {
    return load().map(function (t) { return t.code; });
  }

  window.AffiliationStore = { load: load, save: save, find: find, nameOf: nameOf, codeOf: codeOf, colorOf: colorOf, codes: codes };
})();
