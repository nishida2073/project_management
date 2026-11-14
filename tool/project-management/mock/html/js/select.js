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
    var search = document.createElement('li');
    search.className = 'select-search';
    var input = document.createElement('input');
    input.type = 'text';
    input.addEventListener('click', function (e) { e.stopPropagation(); });
    input.addEventListener('input', function () {
      var q = input.value.trim().toLowerCase();
      menu.querySelectorAll('li[data-opt]').forEach(function (li) {
        li.style.display = (!q || li.getAttribute('data-opt').toLowerCase().indexOf(q) !== -1) ? '' : 'none';
      });
    });
    input.addEventListener('keydown', function (e) {
      if (e.key !== 'Enter') return;
      e.preventDefault();
      var first = Array.prototype.filter.call(menu.querySelectorAll('li[data-opt]'), function (li) { return li.style.display !== 'none'; })[0];
      if (first) first.click();
    });
    search.appendChild(input);
    menu.appendChild(search);
    options.forEach(function (opt) {
      var li = document.createElement('li');
      li.setAttribute('data-opt', opt);
      li.textContent = opt;
      if (opt === current) li.classList.add('selected');
      li.addEventListener('click', function (e) {
        e.stopPropagation();
        selectValue(el, opt);
        el.classList.remove('open');
      });
      menu.appendChild(li);
    });
    var clear = document.createElement('li');
    clear.className = 'select-clear';
    clear.textContent = 'クリア';
    clear.addEventListener('click', function (e) {
      e.stopPropagation();
      selectValue(el, options.indexOf('すべて') >= 0 ? 'すべて' : '選択してください');
      el.setAttribute('data-value', '');
      el.classList.remove('open');
    });
    menu.appendChild(clear);
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

    var target4Selector = el.getAttribute('data-target4');
    var map4Attr = el.getAttribute('data-map4');
    if (target4Selector && map4Attr) {
      var target4 = document.querySelector(target4Selector);
      var map4 = JSON.parse(map4Attr);
      if (target4 && map4[value] !== undefined) {
        var mapped4 = map4[value];
        target4.textContent = mapped4;
        var classMap4Attr = el.getAttribute('data-class-map4');
        if (classMap4Attr) {
          var classMap4 = JSON.parse(classMap4Attr);
          Object.keys(classMap4).forEach(function (k) { target4.classList.remove(classMap4[k]); });
          if (classMap4[mapped4]) target4.classList.add(classMap4[mapped4]);
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
      var menu = el.querySelector('.select-menu');
      var box = el.closest('.modal-body');
      var limit = box ? box.getBoundingClientRect().bottom : window.innerHeight;
      if (menu) {
        var top = box ? box.getBoundingClientRect().top : 0;
        var rect = el.getBoundingClientRect();
        var below = limit - rect.bottom - 8;
        var above = rect.top - top - 8;
        var height = menu.getBoundingClientRect().height;
        if (height > below && above > below) menu.classList.add('up');
        var avail = menu.classList.contains('up') ? above : below;
        if (height > avail) {
          menu.style.maxHeight = Math.max(120, avail) + 'px';
          menu.style.overflowY = 'auto';
        }
      }
      var searchInput = menu ? menu.querySelector('.select-search input') : null;
      if (searchInput) searchInput.focus();
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
