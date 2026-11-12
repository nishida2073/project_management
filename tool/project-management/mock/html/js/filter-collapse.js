(function () {
  function init(panel) {
    var meta = document.querySelector('.table-meta');
    if (!meta) return;
    var wrap = document.createElement('div');
    wrap.className = 'filter-toggle-wrap';
    var label = document.createElement('span');
    label.className = 'filter-toggle-label';
    label.textContent = '検索条件';
    var seg = document.createElement('div');
    seg.className = 'seg';
    var openBtn = document.createElement('button');
    openBtn.type = 'button';
    openBtn.className = 'seg-opt';
    openBtn.textContent = '開く';
    var closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'seg-opt';
    closeBtn.textContent = '閉じる';
    seg.appendChild(openBtn);
    seg.appendChild(closeBtn);
    wrap.appendChild(label);
    wrap.appendChild(seg);
    meta.appendChild(wrap);

    function set(open) {
      panel.classList.toggle('is-collapsed', !open);
      openBtn.classList.toggle('is-active', open);
      closeBtn.classList.toggle('is-active', !open);
    }
    openBtn.addEventListener('click', function () { set(true); });
    closeBtn.addEventListener('click', function () { set(false); });
    set(true);
  }

  document.addEventListener('DOMContentLoaded', function () {
    Array.prototype.forEach.call(document.querySelectorAll('.filter-panel'), init);
  });
})();
