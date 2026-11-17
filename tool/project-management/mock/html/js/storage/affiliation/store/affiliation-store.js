(function () {
  var LIST = [
    { code: 'INTERNAL', name: '社内', color: 'blue' },
    { code: 'PARTNER', name: 'パートナー', color: 'orange' }
  ];

  function load() {
    return LIST.map(function (s) { return { code: s.code, name: s.name, color: s.color }; });
  }

  function find(code) {
    for (var i = 0; i < LIST.length; i++) if (LIST[i].code === code) return LIST[i];
    return null;
  }

  function nameOf(code) {
    var found = find(code);
    return found ? found.name : '';
  }

  function codeOf(name) {
    for (var i = 0; i < LIST.length; i++) if (LIST[i].name === name) return LIST[i].code;
    return '';
  }

  function colorOf(code) {
    var found = find(code);
    return found ? found.color : '';
  }

  window.AffiliationStore = { load: load, find: find, nameOf: nameOf, codeOf: codeOf, colorOf: colorOf };
})();
