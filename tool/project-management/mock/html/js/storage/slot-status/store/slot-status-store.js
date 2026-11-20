(function () {
  var LIST = [
    { code: 'REQUESTED', name: '依頼済', color: 'green' },
    { code: 'REQUESTING', name: '依頼中', color: 'blue' },
    { code: 'BEFORE', name: '依頼前', color: 'orange' },
    { code: 'OPEN', name: '空き枠', color: 'gray' },
    { code: 'OUT_OF_PLAN', name: '予定外', color: 'red' }
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

  function order(code) {
    var i = codes().indexOf(code);
    return i === -1 ? LIST.length : i;
  }

  function tag(s, style, cls) {
    return '<span class="tag ' + (cls ? cls + ' ' : '') + s.color + '"' + (style ? ' style="' + style + '"' : '') + '>' + s.name + '</span>';
  }

  function options(keys) {
    return keys.map(nameOf).join(',');
  }

  function fillDom() {
    document.querySelectorAll('[data-slot-options]').forEach(function (el) {
      el.setAttribute('data-options', options(el.getAttribute('data-slot-options').split(',')));
    });
  }

  fillDom();
  document.addEventListener('DOMContentLoaded', fillDom);

  window.SlotStatusStore = { load: load, STATUS: STATUS, find: find, nameOf: nameOf, colorOf: colorOf, codes: codes, order: order, options: options, tag: tag };
})();
