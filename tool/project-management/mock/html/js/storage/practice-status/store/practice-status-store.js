(function () {
  var LIST = [
    { key: 'BEFORE', label: '実施前', color: 'blue' },
    { key: 'DURING', label: '実施中', color: 'orange' },
    { key: 'AFTER', label: '実施後', color: 'gray' }
  ];

  var STATUS = {};
  LIST.forEach(function (s) { STATUS[s.key] = { label: s.label, tag: s.color }; });

  function find(key) {
    return STATUS[key];
  }

  function labelOf(key) {
    var found = find(key);
    return found ? found.label : '';
  }

  function colorOf(key) {
    var found = find(key);
    return found ? found.tag : '';
  }

  function colorMap() {
    var map = {};
    LIST.forEach(function (s) { map[s.label] = s.color; });
    return map;
  }

  function tag(s, style, cls) {
    return '<span class="tag ' + (cls ? cls + ' ' : '') + s.tag + '"' + (style ? ' style="' + style + '"' : '') + '>' + s.label + '</span>';
  }

  function options(keys) {
    var list = keys ? keys.map(labelOf) : LIST.map(function (s) { return s.label; });
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
      var text = labelOf(el.getAttribute('data-practice-default'));
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

  window.PracticeStatusStore = { STATUS: STATUS, find: find, labelOf: labelOf, colorOf: colorOf, colorMap: colorMap, options: options, tag: tag };
})();
