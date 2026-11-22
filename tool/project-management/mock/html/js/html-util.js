(function () {
  window.esc = function (s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  };
  window.$ = function (id) { return document.getElementById(id); };
  window.ownText = function (el) {
    if (!el) return '';
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
      .map(function (n) { return n.textContent; }).join('').trim();
  };
  window.dashOr = function (v, suffix) {
    return v === undefined || v === null || v === '' ? '-' : window.esc(v) + (suffix || '');
  };
  window.pad2 = function (n) { return String(n).padStart(2, '0'); };
  window.yearLabel = function (v) { return String(v).replace('年度', '') + '年度'; };
  window.placeholderToEmpty = function (s) {
    return s === '選択してください' ? '' : s;
  };
  window.getRadio = function (name) {
    var r = document.querySelector('input[name="' + name + '"]:checked');
    return r ? r.value : '';
  };
  window.checkRadio = function (name, value) {
    var r = document.querySelector('input[name="' + name + '"][value="' + value + '"]');
    if (r) r.checked = true;
  };
  window.getSelect = function (el) {
    return window.ownText(el);
  };
  window.setSelect = function (el, value) {
    var v = value || '';
    el.setAttribute('data-value', v);
    el.innerHTML = (v ? window.esc(v) : '選択してください') + '<span class="caret">▾</span>';
  };
  window.setStatusOff = function (off) {
    var el = window.$('statusToggle');
    if (el) el.classList.toggle('off', !!off);
  };
  window.readStatus = function () {
    var el = window.$('statusToggle');
    return el && el.classList.contains('off') ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE');
  };
  window.bindFormControls = function (root) {
    if (!root) return;
    if (window.bindDatePicker) root.querySelectorAll('.js-date').forEach(function (el) { window.bindDatePicker(el); });
    if (window.bindJsSelect) root.querySelectorAll('.js-select').forEach(function (el) { window.bindJsSelect(el); });
    if (window.bindNumberSelect) root.querySelectorAll('.number-select').forEach(function (el) { window.bindNumberSelect(el); });
  };
  function fmtDate(d) {
    return d.getFullYear() + '/' + String(d.getMonth() + 1).padStart(2, '0') + '/' + String(d.getDate()).padStart(2, '0');
  }
  window.fmtDate = fmtDate;
  window.businessDays = function (startText, endText) {
    function parseDay(s) {
      var m = /^(\d{4})\/(\d{2})\/(\d{2})$/.exec(String(s || '')); return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null;
    }
    var s = parseDay(startText), e = parseDay(endText);
    if (!s || !e || e < s) return '';
    var n = 0;
    for (var d = new Date(s); d <= e; d.setDate(d.getDate() + 1)) {
      var dow = d.getDay();
      var closedDay = window.ClosedDayStore ? ClosedDayStore.isClosedDay(fmtDate(d)) : false;
      if (dow !== 0 && dow !== 6 && !closedDay) n++;
    }
    return n;
  };
  window.classDays = function (cls) {
    return window.businessDays(cls.start, cls.end);
  };
  window.calcEndDate = function (startText, days) {
    if (!/^\d{4}\/\d{2}\/\d{2}$/.test(startText) || !days) return null;
    var d = new Date(startText.replace(/\//g, '-'));
    var remaining = Number(days) - 1;
    while (remaining > 0) {
      d.setDate(d.getDate() + 1);
      var dow = d.getDay();
      var closedDay = window.ClosedDayStore ? window.ClosedDayStore.isClosedDay(fmtDate(d)) : false;
      if (dow !== 0 && dow !== 6 && !closedDay) remaining--;
    }
    return fmtDate(d);
  };
  var tipEl = null;
  function tipShow(el, text) {
    if (!tipEl) { tipEl = document.createElement('div'); tipEl.className = 'tooltip-bubble'; document.body.appendChild(tipEl); }
    tipEl.textContent = text;
    tipEl.style.display = 'block';
    var mark = el.querySelector && el.querySelector('.memo-mark');
    var br = el.getBoundingClientRect();
    var r = mark ? mark.getBoundingClientRect() : (el.classList.contains('has-memo') ? { left: br.right - 18, right: br.right - 2, top: br.top + 2, bottom: br.top + 18, height: 16, width: 16 } : br);
    var rh = r.height || (r.bottom - r.top);
    var cy = r.top + rh / 2;
    var w = tipEl.offsetWidth, hh = tipEl.offsetHeight;
    var rightLeft = r.right + 10;
    if (rightLeft + w <= window.innerWidth - 8) {
      var top0 = Math.max(8, Math.min(window.innerHeight - hh - 8, cy - hh / 2));
      tipEl.classList.remove('below');
      tipEl.classList.add('right');
      tipEl.style.setProperty('--arrow-y', (cy - top0) + 'px');
      tipEl.style.left = rightLeft + 'px';
      tipEl.style.top = top0 + 'px';
      return;
    }
    tipEl.classList.remove('right');
    var left = Math.max(8, Math.min(window.innerWidth - w - 8, r.left + r.width / 2 - w / 2));
    var top = r.top - hh - 10;
    var below = top < 8;
    if (below) top = r.bottom + 10;
    tipEl.classList.toggle('below', below);
    tipEl.style.setProperty('--arrow-x', (r.left + r.width / 2 - left) + 'px');
    tipEl.style.left = left + 'px';
    tipEl.style.top = top + 'px';
  }
  function tipHide() { if (tipEl) tipEl.style.display = 'none'; }
  function tipTarget(e) { return e.target && e.target.closest ? e.target.closest('[data-memo],[data-tip]') : null; }
  document.addEventListener('mouseover', function (e) {
    var el = tipTarget(e);
    if (!el) return;
    var text = el.getAttribute('data-memo') || el.getAttribute('data-tip');
    if (text) tipShow(el, text);
  });
  document.addEventListener('mouseout', function (e) { if (tipTarget(e)) tipHide(); });
  window.TimeUtil = {
    toMinutes: function (t) {
      var p = String(t).split(':');
      return Number(p[0]) * 60 + Number(p[1]);
    },
    toTime: function (m) {
      return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0');
    }
  };
})();
