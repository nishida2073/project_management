(function () {
  window.__ddClosers = window.__ddClosers || [];

  function closeMine() {
    document.querySelectorAll('.js-select.open').forEach(function (el) {
      el.classList.remove('open');
      var menu = el.querySelector('.select-menu');
      if (menu) menu.remove();
    });
  }
  window.__ddClosers.push(closeMine);

  function closeOthers() {
    window.__ddClosers.forEach(function (fn) { fn(); });
  }

  function buildMenu(el) {
    var options = (el.getAttribute('data-options') || '').split(',').map(function (s) { return s.trim(); }).filter(Boolean);
    var menu = document.createElement('ul');
    menu.className = 'select-menu';
    var current = el.getAttribute('data-value') || '';
    options.forEach(function (opt) {
      var li = document.createElement('li');
      li.textContent = opt;
      if (opt === current) li.classList.add('selected');
      li.addEventListener('click', function (e) {
        e.stopPropagation();
        selectValue(el, opt);
        el.classList.remove('open');
      });
      menu.appendChild(li);
    });
    return menu;
  }

  function selectValue(el, value) {
    el.setAttribute('data-value', value);
    var caret = el.querySelector('.caret');
    el.textContent = value;
    if (caret) el.appendChild(caret);
    else el.insertAdjacentHTML('beforeend', '<span class="caret">▾</span>');

    var targetSelector = el.getAttribute('data-target');
    var mapAttr = el.getAttribute('data-map');
    if (targetSelector && mapAttr) {
      var target = document.querySelector(targetSelector);
      var map = JSON.parse(mapAttr);
      if (target && map[value] !== undefined) target.textContent = map[value];
    }
  }

  document.querySelectorAll('.js-select').forEach(function (el) {
    if (!el.hasAttribute('data-value')) {
      var firstNode = el.childNodes[0];
      var text = (firstNode && firstNode.nodeType === 3 ? firstNode.textContent : '').trim();
      if (text && text !== '選択してください') el.setAttribute('data-value', text);
    }
    el.addEventListener('click', function (e) {
      e.stopPropagation();
      var isOpen = el.classList.contains('open');
      closeOthers();
      if (isOpen) return;
      el.appendChild(buildMenu(el));
      el.classList.add('open');
    });
  });

  document.addEventListener('click', function () {
    closeOthers();
  });
})();
