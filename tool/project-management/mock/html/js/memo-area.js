(function () {
  var SELECTOR = 'textarea.memo-area, textarea.auto-grow';

  function fit(t) {
    var min = parseInt(t.getAttribute('data-min'), 10) || 30;
    t.style.height = 'auto';
    t.style.height = Math.max(min, t.scrollHeight + 2) + 'px';
  }

  function fitAll() {
    Array.prototype.forEach.call(document.querySelectorAll(SELECTOR), fit);
  }

  document.addEventListener('input', function (e) {
    if (e.target && e.target.matches && e.target.matches(SELECTOR)) fit(e.target);
  });

  fitAll();
})();
