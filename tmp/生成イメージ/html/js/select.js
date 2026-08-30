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

    var target2Selector = el.getAttribute('data-target2');
    var map2Attr = el.getAttribute('data-map2');
    if (target2Selector && map2Attr) {
      var target2 = document.querySelector(target2Selector);
      var map2 = JSON.parse(map2Attr);
      if (target2 && map2[value] !== undefined) {
        var mapped2 = map2[value];
        target2.textContent = mapped2;
        var classMap2Attr = el.getAttribute('data-class-map2');
        if (classMap2Attr) {
          var classMap2 = JSON.parse(classMap2Attr);
          Object.keys(classMap2).forEach(function (k) { target2.classList.remove(classMap2[k]); });
          if (classMap2[mapped2]) target2.classList.add(classMap2[mapped2]);
        }
      }
    }

    var target3Selector = el.getAttribute('data-target3');
    var map3Attr = el.getAttribute('data-map3');
    if (target3Selector && map3Attr) {
      var target3 = document.querySelector(target3Selector);
      var map3 = JSON.parse(map3Attr);
      if (target3 && map3[value] !== undefined) {
        var mapped3 = map3[value];
        target3.textContent = mapped3;
        var classMap3Attr = el.getAttribute('data-class-map3');
        if (classMap3Attr) {
          var classMap3 = JSON.parse(classMap3Attr);
          Object.keys(classMap3).forEach(function (k) { target3.classList.remove(classMap3[k]); });
          if (classMap3[mapped3]) target3.classList.add(classMap3[mapped3]);
        }
      }
    }

    var classMapAttr = el.getAttribute('data-class-map');
    if (classMapAttr) {
      var classMap = JSON.parse(classMapAttr);
      Object.keys(classMap).forEach(function (k) { el.classList.remove(classMap[k]); });
      if (classMap[value]) el.classList.add(classMap[value]);
    }

    var optionsMapAttr = el.getAttribute('data-options-map');
    if (targetSelector && optionsMapAttr) {
      var mapTarget = document.querySelector(targetSelector);
      var optionsMap = JSON.parse(optionsMapAttr);
      if (mapTarget && optionsMap[value] !== undefined) {
        if (mapTarget.classList.contains('js-chip-select') && window.chipSelectSetOptions) {
          window.chipSelectSetOptions(mapTarget, optionsMap[value]);
        } else if (mapTarget.classList.contains('js-select')) {
          jsSelectSetOptions(mapTarget, optionsMap[value]);
        }
      }
    }
  }

  function jsSelectSetOptions(el, newOptions) {
    el.setAttribute('data-options', newOptions.join(','));
    var current = el.getAttribute('data-value') || '';
    if (current && newOptions.indexOf(current) === -1) {
      el.removeAttribute('data-value');
      var caret = el.querySelector('.caret');
      el.textContent = '選択してください';
      if (caret) el.appendChild(caret);
      else el.insertAdjacentHTML('beforeend', '<span class="caret">▾</span>');

      var targetSelector = el.getAttribute('data-target');
      var mapAttr = el.getAttribute('data-map');
      if (targetSelector && mapAttr) {
        var target = document.querySelector(targetSelector);
        if (target) target.textContent = '選択すると自動入力されます';
      }

      var target2Selector = el.getAttribute('data-target2');
      var map2Attr = el.getAttribute('data-map2');
      if (target2Selector && map2Attr) {
        var target2 = document.querySelector(target2Selector);
        if (target2) {
          target2.textContent = '';
          var classMap2Attr = el.getAttribute('data-class-map2');
          if (classMap2Attr) {
            var classMap2 = JSON.parse(classMap2Attr);
            Object.keys(classMap2).forEach(function (k) { target2.classList.remove(classMap2[k]); });
          }
        }
      }

      var target3Selector = el.getAttribute('data-target3');
      var map3Attr = el.getAttribute('data-map3');
      if (target3Selector && map3Attr) {
        var target3 = document.querySelector(target3Selector);
        if (target3) {
          target3.textContent = '';
          var classMap3Attr = el.getAttribute('data-class-map3');
          if (classMap3Attr) {
            var classMap3 = JSON.parse(classMap3Attr);
            Object.keys(classMap3).forEach(function (k) { target3.classList.remove(classMap3[k]); });
          }
        }
      }
    }
  }
  window.jsSelectSetOptions = jsSelectSetOptions;

  function bindSelect(el) {
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
  }
  window.bindJsSelect = bindSelect;

  document.querySelectorAll('.js-select').forEach(bindSelect);

  document.addEventListener('click', function () {
    closeOthers();
  });

  document.querySelectorAll('.radio-group[data-target][data-options-map]').forEach(function (group) {
    var targetSelector = group.getAttribute('data-target');
    var optionsMap = JSON.parse(group.getAttribute('data-options-map'));
    group.querySelectorAll('input[type="radio"]').forEach(function (radio) {
      radio.addEventListener('change', function () {
        var target = document.querySelector(targetSelector);
        if (!target || optionsMap[radio.value] === undefined) return;
        if (target.classList.contains('js-chip-select') && window.chipSelectSetOptions) {
          window.chipSelectSetOptions(target, optionsMap[radio.value]);
        } else if (target.classList.contains('js-select')) {
          jsSelectSetOptions(target, optionsMap[radio.value]);
        }
      });
    });
  });
})();
