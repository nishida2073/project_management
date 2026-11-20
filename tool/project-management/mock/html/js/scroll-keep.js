(function () {
  var KEY = 'scrollKeep:' + location.pathname;
  var SELECTORS = ['.table-scroll', '.progress-scroll', '.scroll-outer', '.cal-body'];

  function read() {
    try { return JSON.parse(sessionStorage.getItem(KEY) || '{}'); } catch (e) { return {}; }
  }

  function visible(el) {
    return el.getClientRects().length > 0;
  }

  function save() {
    var map = read();
    map.window = { x: window.scrollX, y: window.scrollY };
    SELECTORS.forEach(function (sel) {
      document.querySelectorAll(sel).forEach(function (el, i) {
        if (!visible(el)) return;
        map[sel + '#' + i] = { top: el.scrollTop, left: el.scrollLeft };
      });
    });
    try { sessionStorage.setItem(KEY, JSON.stringify(map)); } catch (e) {}
  }

  function take(key) {
    var map = read();
    var value = map[key] || null;
    if (value) {
      delete map[key];
      try { sessionStorage.setItem(KEY, JSON.stringify(map)); } catch (e) {}
    }
    return value;
  }

  function restore() {
    var map = read();
    SELECTORS.forEach(function (sel) {
      document.querySelectorAll(sel).forEach(function (el, i) {
        var p = map[sel + '#' + i];
        if (!p || !visible(el)) return;
        el.scrollTop = p.top;
        el.scrollLeft = p.left;
        delete map[sel + '#' + i];
      });
    });
    if (map.window) window.scrollTo(map.window.x, map.window.y);
    try { sessionStorage.setItem(KEY, JSON.stringify(map)); } catch (e) {}
  }

  window.ScrollKeep = { save: save, take: take };
  window.addEventListener('pagehide', save);
  document.addEventListener('DOMContentLoaded', restore);
})();
