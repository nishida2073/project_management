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
  window.setStatusOff = function (off) {
    var el = window.$('statusToggle');
    if (el) el.classList.toggle('off', !!off);
  };
  window.readStatus = function () {
    var el = window.$('statusToggle');
    return el && el.classList.contains('off') ? '停止中' : '稼働中';
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
  window.calcEndDate = function (startText, days) {
    if (!/^\d{4}\/\d{2}\/\d{2}$/.test(startText) || !days) return null;
    var d = new Date(startText.replace(/\//g, '-'));
    var remaining = Number(days) - 1;
    while (remaining > 0) {
      d.setDate(d.getDate() + 1);
      var dow = d.getDay();
      var holiday = window.HolidayStore ? window.HolidayStore.isHoliday(fmtDate(d)) : false;
      if (dow !== 0 && dow !== 6 && !holiday) remaining--;
    }
    return fmtDate(d);
  };
})();
