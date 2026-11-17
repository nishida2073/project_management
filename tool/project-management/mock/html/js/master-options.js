(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function fillOptions() {
    document.querySelectorAll('[data-master-options]').forEach(function (el) {
      var store = window[el.getAttribute('data-master-options')];
      if (!store) return;
      var names = store.load().map(function (r) { return r.name; });
      el.setAttribute('data-options', ['すべて'].concat(names).join(','));
    });
  }

  function fillRadios() {
    document.querySelectorAll('[data-master-radio]').forEach(function (el) {
      if (el.getAttribute('data-generated')) return;
      var store = window[el.getAttribute('data-master-radio')];
      if (!store) return;
      var name = el.getAttribute('data-radio-name');
      el.innerHTML = store.load().map(function (r) {
        return '<label class="radio-option"><input type="radio" name="' + esc(name) + '" value="' + esc(r.name) + '"><span class="radio-dot"></span><span class="tag ' + esc(r.color) + '">' + esc(r.name) + '</span></label>';
      }).join('');
      el.setAttribute('data-generated', '1');
    });
  }

  function fillTabs() {
    document.querySelectorAll('[data-master-tab]').forEach(function (el) {
      var store = window[el.getAttribute('data-master-tab')];
      if (!store) return;
      var code = el.getAttribute('data-code');
      var found = store.load().filter(function (r) { return r.code === code; })[0];
      if (!found) return;
      el.textContent = found.name;
      el.setAttribute('data-tt', found.name);
    });
  }

  function fill() {
    fillRadios();
    fillTabs();
    fillOptions();
  }

  fill();
  document.addEventListener('DOMContentLoaded', fill);
})();
