(function () {
  var LIST = [
    { code: 'BEFORE', name: '実施前', color: 'blue' },
    { code: 'DURING', name: '実施中', color: 'orange' },
    { code: 'AFTER', name: '実施後', color: 'gray' }
  ];

  var STATUS = {};
  LIST.forEach(function (s) { STATUS[s.code] = { code: s.code, name: s.name, color: s.color }; });

  function load() {
    return LIST.map(function (s) { return { code: s.code, name: s.name, color: s.color }; });
  }

  function find(code) {
    return STATUS[code];
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
    return LIST.map(function (s) { return s.code; });
  }

  function colorMap() {
    var map = {};
    LIST.forEach(function (s) { map[s.name] = s.color; });
    return map;
  }

  function tag(s, style, cls) {
    return '<span class="tag ' + (cls ? cls + ' ' : '') + s.color + '"' + (style ? ' style="' + style + '"' : '') + '>' + s.name + '</span>';
  }

  function options(keys) {
    var list = keys ? keys.map(nameOf) : LIST.map(function (s) { return s.name; });
    return list.join(',');
  }

  function fillDom() {
    document.querySelectorAll('[data-practice-options]').forEach(function (el) {
      el.setAttribute('data-options', 'すべて,' + options());
    });
    document.querySelectorAll('[data-practice-options-active]').forEach(function (el) {
      el.setAttribute('data-options', 'すべて,' + options(['BEFORE', 'DURING']));
    });
    document.querySelectorAll('[data-practice-default]').forEach(function (el) {
      var text = nameOf(el.getAttribute('data-practice-default'));
      el.setAttribute('data-value', text);
      var first = el.firstChild;
      if (first && first.nodeType === 3) {
        if (!first.nodeValue.trim()) first.nodeValue = text;
      } else {
        el.insertBefore(document.createTextNode(text), el.firstChild);
      }
    });
  }

  fillDom();
  document.addEventListener('DOMContentLoaded', fillDom);

  window.PracticeStatusStore = { load: load, STATUS: STATUS, find: find, nameOf: nameOf, colorOf: colorOf, codes: codes, colorMap: colorMap, options: options, tag: tag };
})();
