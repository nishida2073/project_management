(function () {
  function pad(n) { return n < 10 ? '0' + n : '' + n; }

  function parseDate(str) {
    var m = /^(\d{4})\/(\d{2})\/(\d{2})$/.exec(str || '');
    return m ? { y: +m[1], m: +m[2], d: +m[3] } : null;
  }

  function parseMonth(str) {
    var m = /^(\d{4})\/(\d{2})$/.exec(str || '');
    return m ? { y: +m[1], m: +m[2] } : null;
  }

  function today() {
    var t = new Date();
    return { y: t.getFullYear(), m: t.getMonth() + 1, d: t.getDate() };
  }

  window.__ddClosers = window.__ddClosers || [];

  function closeMine() {
    document.querySelectorAll('.js-date.open, .js-month.open').forEach(function (el) {
      el.classList.remove('open');
      var picker = el.querySelector('.date-picker');
      if (picker) picker.remove();
    });
  }
  window.__ddClosers.push(closeMine);

  function closeOthers() {
    window.__ddClosers.forEach(function (fn) { fn(); });
  }

  function setValue(el, text) {
    el.setAttribute('data-value', text);
    var caret = el.querySelector('.caret');
    el.textContent = text;
    if (caret) el.appendChild(caret);
    else el.insertAdjacentHTML('beforeend', '<span class="caret">▾</span>');
  }

  function buildDatePicker(el) {
    var current = parseDate(el.getAttribute('data-value')) || today();
    var viewY = current.y, viewM = current.m;
    var wrap = document.createElement('div');
    wrap.className = 'date-picker';

    function render() {
      wrap.innerHTML = '';
      var head = document.createElement('div');
      head.className = 'dp-head';
      var prev = document.createElement('span');
      prev.className = 'dp-nav';
      prev.textContent = '‹';
      var label = document.createElement('span');
      label.textContent = viewY + '年' + pad(viewM) + '月';
      var next = document.createElement('span');
      next.className = 'dp-nav';
      next.textContent = '›';
      head.appendChild(prev);
      head.appendChild(label);
      head.appendChild(next);
      wrap.appendChild(head);

      prev.addEventListener('click', function (e) {
        e.stopPropagation();
        viewM--; if (viewM < 1) { viewM = 12; viewY--; }
        render();
      });
      next.addEventListener('click', function (e) {
        e.stopPropagation();
        viewM++; if (viewM > 12) { viewM = 1; viewY++; }
        render();
      });

      var grid = document.createElement('div');
      grid.className = 'dp-grid';
      ['日', '月', '火', '水', '木', '金', '土'].forEach(function (d) {
        var dow = document.createElement('div');
        dow.className = 'dp-dow';
        dow.textContent = d;
        grid.appendChild(dow);
      });

      var firstDow = new Date(viewY, viewM - 1, 1).getDay();
      var daysInMonth = new Date(viewY, viewM, 0).getDate();
      var prevMonthDays = new Date(viewY, viewM - 1, 0).getDate();

      for (var i = 0; i < firstDow; i++) {
        var muted = document.createElement('div');
        muted.className = 'dp-day muted';
        muted.textContent = prevMonthDays - firstDow + 1 + i;
        grid.appendChild(muted);
      }
      for (var d = 1; d <= daysInMonth; d++) {
        var cell = document.createElement('div');
        cell.className = 'dp-day';
        cell.textContent = d;
        if (current.y === viewY && current.m === viewM && current.d === d) cell.classList.add('selected');
        (function (dd) {
          cell.addEventListener('click', function (e) {
            e.stopPropagation();
            setValue(el, viewY + '/' + pad(viewM) + '/' + pad(dd));
            el.classList.remove('open');
          });
        })(d);
        grid.appendChild(cell);
      }
      var totalCells = firstDow + daysInMonth;
      var trailing = (7 - (totalCells % 7)) % 7;
      for (var t = 1; t <= trailing; t++) {
        var muted2 = document.createElement('div');
        muted2.className = 'dp-day muted';
        muted2.textContent = t;
        grid.appendChild(muted2);
      }
      wrap.appendChild(grid);
    }
    render();
    return wrap;
  }

  function buildMonthPicker(el) {
    var current = parseMonth(el.getAttribute('data-value')) || today();
    var viewY = current.y;
    var wrap = document.createElement('div');
    wrap.className = 'date-picker month-picker';

    function render() {
      wrap.innerHTML = '';
      var head = document.createElement('div');
      head.className = 'dp-head';
      var prev = document.createElement('span');
      prev.className = 'dp-nav';
      prev.textContent = '‹';
      var label = document.createElement('span');
      label.textContent = viewY + '年';
      var next = document.createElement('span');
      next.className = 'dp-nav';
      next.textContent = '›';
      head.appendChild(prev);
      head.appendChild(label);
      head.appendChild(next);
      wrap.appendChild(head);

      prev.addEventListener('click', function (e) { e.stopPropagation(); viewY--; render(); });
      next.addEventListener('click', function (e) { e.stopPropagation(); viewY++; render(); });

      var grid = document.createElement('div');
      grid.className = 'dp-grid';
      for (var m = 1; m <= 12; m++) {
        var cell = document.createElement('div');
        cell.className = 'dp-month';
        cell.textContent = m + '月';
        if (current.y === viewY && current.m === m) cell.classList.add('selected');
        (function (mm) {
          cell.addEventListener('click', function (e) {
            e.stopPropagation();
            setValue(el, viewY + '/' + pad(mm));
            el.classList.remove('open');
          });
        })(m);
        grid.appendChild(cell);
      }
      wrap.appendChild(grid);
    }
    render();
    return wrap;
  }

  function bind(selector, builder) {
    document.querySelectorAll(selector).forEach(function (el) {
      if (!el.hasAttribute('data-value')) {
        var firstNode = el.childNodes[0];
        var text = (firstNode && firstNode.nodeType === 3 ? firstNode.textContent : '').trim();
        if (/^\d{4}\/\d{2}(\/\d{2})?$/.test(text)) el.setAttribute('data-value', text);
      }
      el.addEventListener('click', function (e) {
        e.stopPropagation();
        var isOpen = el.classList.contains('open');
        closeOthers();
        if (isOpen) return;
        el.appendChild(builder(el));
        el.classList.add('open');
      });
    });
  }

  bind('.js-date', buildDatePicker);
  bind('.js-month', buildMonthPicker);

  document.addEventListener('click', function () {
    closeOthers();
  });
})();
