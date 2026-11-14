(function () {
  function norm(s) {
    return String(s || '').replace(/\s+/g, ' ').trim().toLowerCase();
  }
  function ownText(el) {
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
      .map(function (n) { return n.textContent; }).join('').trim();
  }
  function parseDate(s) {
    var m = /^(\d{4})\/(\d{1,2})\/(\d{1,2})$/.exec(String(s || '').trim());
    return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])).getTime() : null;
  }

  function parseMonth(s) {
    var m = /^(\d{4})\/(\d{1,2})$/.exec(String(s || '').trim());
    return m ? Number(m[1]) * 100 + Number(m[2]) : null;
  }

  document.addEventListener('DOMContentLoaded', function () {
    var panel = document.querySelector('.filter-panel');
    var table = document.querySelector('.table-card table');
    if (!panel || !table) return;
    var tbody = table.querySelector('tbody');
    if (!tbody) return;

    var texts = Array.prototype.slice.call(panel.querySelectorAll('input.field-control-input, input.form-control'));
    var selects = Array.prototype.slice.call(panel.querySelectorAll('.js-select'));
    var dates = Array.prototype.slice.call(panel.querySelectorAll('.js-date'));
    var countEl = document.querySelector('.table-meta .count b');
    var rows = Array.prototype.slice.call(tbody.querySelectorAll('tr'));

    function selValue(el) {
      var v = el.getAttribute('data-value');
      if (v === null || v === '') v = ownText(el);
      return String(v || '').trim();
    }

    function apply() {
      var keywords = texts.map(function (i) { return norm(i.value); }).filter(Boolean);
      var chosen = selects.map(function (el) {
        return { v: selValue(el), cls: el.getAttribute('data-match-class'), col: el.getAttribute('data-match-col'), attr: el.getAttribute('data-match-attr') };
      }).filter(function (c) { return c.v && c.v !== 'すべて' && c.v !== '選択してください'; });
      var from = dates[0] ? parseDate(ownText(dates[0])) : null;
      var to = dates[1] ? parseDate(ownText(dates[1])) : null;
      var months = Array.prototype.slice.call(panel.querySelectorAll('.js-month'));
      var mFrom = months[0] ? parseMonth(ownText(months[0])) : null;
      var mTo = months[1] ? parseMonth(ownText(months[1])) : null;
      var shown = 0;

      rows.forEach(function (tr) {
        var text = norm(tr.textContent);
        var ok = keywords.every(function (k) { return text.indexOf(k) !== -1; }) &&
          chosen.every(function (c) {
            if (c.cls) {
              var byClass = tr.querySelector('.' + c.cls);
              return !!byClass && norm(byClass.textContent) === norm(c.v);
            }
            if (c.col !== null) {
              var cell = tr.children[Number(c.col)];
              return !!cell && norm(cell.textContent) === norm(c.v);
            }
            if (c.attr) {
              return String(tr.getAttribute(c.attr) || '').split('|').indexOf(c.v) !== -1;
            }
            return text.indexOf(norm(c.v)) !== -1;
          });
        if (ok && (from !== null || to !== null)) {
          var times = Array.prototype.map.call(tr.querySelectorAll('td'), function (td) {
            return parseDate(td.textContent);
          }).filter(function (t) { return t !== null; });
          ok = times.some(function (t) {
            return (from === null || t >= from) && (to === null || t <= to);
          });
        }
        if (ok && (mFrom !== null || mTo !== null)) {
          var mons = Array.prototype.map.call(tr.querySelectorAll('td'), function (td) {
            return parseMonth(td.textContent);
          }).filter(function (m) { return m !== null; });
          ok = mons.some(function (m) {
            return (mFrom === null || m >= mFrom) && (mTo === null || m <= mTo);
          });
        }
        tr.style.display = ok ? '' : 'none';
        tr.setAttribute('data-match', ok ? '1' : '0');
        if (ok) shown++;
      });

      if (countEl) countEl.textContent = shown;
      if (window.listPaginate) window.listPaginate(true);
    }

    var button = panel.querySelector('.search-btn');
    if (button) button.addEventListener('click', apply);
    texts.forEach(function (input) {
      input.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') apply();
      });
    });
  });
})();
