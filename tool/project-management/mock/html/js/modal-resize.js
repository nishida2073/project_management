(function () {
  var base = document.querySelector('.modal-resize');
  if (!base) return;
  var modal = base.closest('.modal');
  var dirs = { r: [1, 0], l: [-1, 0], b: [0, 1], t: [0, -1] };

  base.classList.add('r');
  Object.keys(dirs).forEach(function (d) {
    var h = base;
    if (d !== 'r') {
      h = document.createElement('div');
      h.className = 'modal-resize ' + d;
      modal.appendChild(h);
    }
    h.addEventListener('mousedown', function (e) { start(e, dirs[d]); });
  });

  function start(e, dir) {
    e.preventDefault();
    var rect = modal.getBoundingClientRect();
    var startX = e.clientX;
    var startY = e.clientY;
    var startW = rect.width;
    var startH = rect.height;

    function onMove(ev) {
      modal.style.maxWidth = 'none';
      modal.style.maxHeight = 'none';
      if (dir[0]) modal.style.width = Math.max(480, startW + 2 * dir[0] * (ev.clientX - startX)) + 'px';
      if (dir[1]) modal.style.height = Math.max(300, startH + 2 * dir[1] * (ev.clientY - startY)) + 'px';
    }

    function onUp() {
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup', onUp);
    }

    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
  }
})();
