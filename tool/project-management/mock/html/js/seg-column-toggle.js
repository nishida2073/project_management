(function () {
  var styleEl = document.createElement('style');
  document.head.appendChild(styleEl);
  var ruled = {};

  function ensureRule(cls) {
    if (ruled[cls]) return;
    ruled[cls] = true;
    styleEl.appendChild(document.createTextNode('table.hide-' + cls + ' .' + cls + ' { display: none; }\n'));
  }

  function apply(seg, hide) {
    var cls = seg.getAttribute('data-hide-class');
    var table = document.querySelector(seg.getAttribute('data-target') || 'table');
    if (!cls || !table) return;
    ensureRule(cls);
    table.classList.toggle('hide-' + cls, hide);
    if (table.__relayout) table.__relayout();
  }

  document.querySelectorAll('.seg[data-hide-class]').forEach(function (seg) {
    var opts = seg.querySelectorAll('.seg-opt');
    Array.prototype.forEach.call(opts, function (btn) {
      btn.addEventListener('click', function () {
        Array.prototype.forEach.call(opts, function (b) { b.classList.toggle('is-active', b === btn); });
        apply(seg, btn.getAttribute('data-v') === 'hide');
      });
    });
    var active = seg.querySelector('.seg-opt.is-active');
    if (active && active.getAttribute('data-v') === 'hide') apply(seg, true);
  });
})();
