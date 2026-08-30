(function () {
  window.__ddClosers = window.__ddClosers || [];

  function closeMine() {
    document.querySelectorAll('.number-select.open').forEach(function (el) {
      el.classList.remove('open');
      var menu = el.querySelector('.select-menu');
      if (menu) menu.remove();
    });
  }
  window.__ddClosers.push(closeMine);

  function closeOthers() {
    window.__ddClosers.forEach(function (fn) { fn(); });
  }

  document.querySelectorAll('.number-select').forEach(function (el) {
    var input = el.querySelector('input');
    var caret = el.querySelector('.caret');
    var options = (el.getAttribute('data-options') || '').split(',').map(function (s) { return s.trim(); }).filter(Boolean);

    if (!caret || !input || !options.length) return;

    caret.addEventListener('click', function (e) {
      e.stopPropagation();
      var isOpen = el.classList.contains('open');
      closeOthers();
      if (isOpen) return;
      var menu = document.createElement('ul');
      menu.className = 'select-menu';
      options.forEach(function (opt) {
        var li = document.createElement('li');
        li.textContent = opt;
        if (opt === input.value.trim()) li.classList.add('selected');
        li.addEventListener('click', function (e2) {
          e2.stopPropagation();
          input.value = opt;
          el.classList.remove('open');
          input.focus();
        });
        menu.appendChild(li);
      });
      el.appendChild(menu);
      el.classList.add('open');
    });
  });

  document.addEventListener('click', function () {
    closeOthers();
  });
})();
