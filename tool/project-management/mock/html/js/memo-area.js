(function () {
  var MIN = 30;

  function fit(t) {
    t.style.height = 'auto';
    t.style.height = Math.max(MIN, t.scrollHeight + 2) + 'px';
  }

  function fitAll() {
    Array.prototype.forEach.call(document.querySelectorAll('textarea.memo-area'), fit);
  }

  document.addEventListener('input', function (e) {
    if (e.target && e.target.matches && e.target.matches('textarea.memo-area')) fit(e.target);
  });

  fitAll();
})();
