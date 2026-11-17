(function () {
  var LIST = [
    { key: 'WAIT', label: '実施前', color: 'gray' },
    { key: 'PROGRESS', label: '実施中', color: 'blue' },
    { key: 'DONE', label: '完了', color: 'green' },
    { key: 'NA', label: '対象外', color: 'gray', selectable: false }
  ];

  function byKey(key) {
    for (var i = 0; i < LIST.length; i++) if (LIST[i].key === key) return LIST[i];
    return null;
  }

  function labelOf(key) {
    var s = byKey(key);
    return s ? s.label : '';
  }

  function colorOf(key) {
    var s = byKey(key);
    return s ? s.color : '';
  }

  function keyOfLabel(label) {
    for (var i = 0; i < LIST.length; i++) if (LIST[i].label === label) return LIST[i].key;
    return '';
  }

  function options() {
    return LIST.filter(function (s) { return s.selectable !== false; }).map(function (s) { return s.label; }).join(',');
  }

  function byLabel() {
    var map = {};
    LIST.forEach(function (s) { map[s.label] = s.key; });
    return map;
  }

  function labelByKey() {
    var map = {};
    LIST.forEach(function (s) { map[s.key] = s.label; });
    return map;
  }

  function classMapJson() {
    var map = {};
    LIST.forEach(function (s) { map[s.label] = s.color; });
    return JSON.stringify(map);
  }

  window.StepStatusStore = {
    LIST: LIST, labelOf: labelOf, colorOf: colorOf, keyOfLabel: keyOfLabel,
    options: options, byLabel: byLabel, labelByKey: labelByKey, classMapJson: classMapJson
  };
})();
