(function () {
  var LIST = [
    { code: 'WAIT', name: '実施前', color: 'gray' },
    { code: 'PROGRESS', name: '実施中', color: 'blue' },
    { code: 'DONE', name: '完了', color: 'green' },
    { code: 'NA', name: '対象外', color: 'gray', selectable: false }
  ];

  function load() {
    return LIST.map(function (s) { return { code: s.code, name: s.name, color: s.color, selectable: s.selectable }; });
  }

  function find(code) {
    for (var i = 0; i < LIST.length; i++) if (LIST[i].code === code) return LIST[i];
    return null;
  }

  function nameOf(code) {
    var s = find(code);
    return s ? s.name : '';
  }

  function colorOf(code) {
    var s = find(code);
    return s ? s.color : '';
  }

  function codeOf(name) {
    for (var i = 0; i < LIST.length; i++) if (LIST[i].name === name) return LIST[i].code;
    return '';
  }

  function codes() {
    return LIST.map(function (s) { return s.code; });
  }

  function options() {
    return LIST.filter(function (s) { return s.selectable !== false; }).map(function (s) { return s.name; }).join(',');
  }

  function byName() {
    var map = {};
    LIST.forEach(function (s) { map[s.name] = s.code; });
    return map;
  }

  function nameByCode() {
    var map = {};
    LIST.forEach(function (s) { map[s.code] = s.name; });
    return map;
  }

  function classMapJson() {
    var map = {};
    LIST.forEach(function (s) { map[s.name] = s.color; });
    return JSON.stringify(map);
  }

  window.StepStatusStore = {
    load: load, find: find, nameOf: nameOf, colorOf: colorOf, codeOf: codeOf, codes: codes,
    options: options, byName: byName, nameByCode: nameByCode, classMapJson: classMapJson
  };
})();
