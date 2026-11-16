(function () {
  var KEY = 'filterMemory:' + location.pathname;

  function panel() { return document.querySelector('.filter-panel'); }
  function texts(p) { return Array.prototype.slice.call(p.querySelectorAll('input.field-control-input, input.form-control')); }
  function selects(p) { return Array.prototype.slice.call(p.querySelectorAll('.js-select')); }
  function dates(p) { return Array.prototype.slice.call(p.querySelectorAll('.js-date')); }

  function textOf(el) {
    var t = '';
    Array.prototype.forEach.call(el.childNodes, function (n) { if (n.nodeType === 3) t += n.nodeValue; });
    return t.trim();
  }

  function setText(el, v) {
    var node = Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })[0];
    if (node) node.nodeValue = v;
    else el.insertBefore(document.createTextNode(v), el.firstChild);
  }

  function collect(p) {
    return {
      texts: texts(p).map(function (i) { return i.value; }),
      selects: selects(p).map(function (el) {
        return { text: textOf(el), value: el.getAttribute('data-value') };
      }),
      dates: dates(p).map(function (el) { return textOf(el); })
    };
  }

  function applyState(p, s) {
    texts(p).forEach(function (el, i) {
      if (s.texts && s.texts[i] !== undefined) el.value = s.texts[i];
    });
    selects(p).forEach(function (el, i) {
      var v = s.selects && s.selects[i];
      if (!v || !v.text) return;
      if (v.value !== null) el.setAttribute('data-value', v.value);
      setText(el, v.text);
    });
    dates(p).forEach(function (el, i) {
      var v = s.dates && s.dates[i];
      if (v !== undefined) setText(el, v);
    });
  }

  function save() {
    var p = panel();
    if (!p) return;
    try { localStorage.setItem(KEY, JSON.stringify(collect(p))); } catch (e) {}
  }

  document.addEventListener('DOMContentLoaded', function () {
    var p = panel();
    if (!p) return;
    var initial = collect(p);
    var saved = null;
    try { saved = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { saved = null; }
    var searchBtn = p.querySelector('.search-btn');
    if (saved) {
      applyState(p, saved);
      if (searchBtn) searchBtn.click();
    }
    if (searchBtn) searchBtn.addEventListener('click', save);
    texts(p).forEach(function (input) {
      input.addEventListener('keydown', function (e) { if (e.key === 'Enter') save(); });
    });
    var resetBtn = document.getElementById('resetFilter');
    if (resetBtn) {
      resetBtn.addEventListener('click', function () {
        applyState(p, initial);
        if (searchBtn) searchBtn.click();
        try { localStorage.removeItem(KEY); } catch (e) {}
      });
    }
  });
})();
