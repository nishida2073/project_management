(function () {
  window.__ddClosers = window.__ddClosers || [];

  function closeMine() {
    document.querySelectorAll('.js-chip-select.open').forEach(function (box) {
      box.classList.remove('open');
      var menu = box.querySelector('.select-menu');
      if (menu) menu.remove();
    });
  }
  window.__ddClosers.push(closeMine);

  function closeOthers() {
    window.__ddClosers.forEach(function (fn) { fn(); });
  }

  function currentValues(box) {
    return Array.prototype.map.call(box.querySelectorAll('.chip'), function (chip) {
      var firstNode = chip.childNodes[0];
      return (firstNode && firstNode.nodeType === 3 ? firstNode.textContent : '').trim();
    });
  }

  function bindRemove(chip) {
    var x = chip.querySelector('x');
    if (x) x.addEventListener('click', function (e) {
      e.stopPropagation();
      chip.remove();
    });
  }

  function makeChip(value, chipClass) {
    var chip = document.createElement('span');
    chip.className = 'chip' + (chipClass ? ' ' + chipClass : '');
    chip.appendChild(document.createTextNode(value + ' '));
    var x = document.createElement('x');
    x.textContent = '✕';
    chip.appendChild(x);
    bindRemove(chip);
    return chip;
  }

  function chipClassFor(box, value) {
    var mapAttr = box.getAttribute('data-chip-map');
    if (mapAttr) {
      var map = JSON.parse(mapAttr);
      if (map[value]) return map[value];
    }
    return box.getAttribute('data-chip-class') || '';
  }

  function readOptions(box) {
    return (box.getAttribute('data-options') || '').split(',').map(function (s) { return s.trim(); }).filter(Boolean);
  }

  window.chipSelectSetOptions = function (box, newOptions) {
    box.setAttribute('data-options', newOptions.join(','));
    box.querySelectorAll('.chip').forEach(function (chip) {
      var firstNode = chip.childNodes[0];
      var val = (firstNode && firstNode.nodeType === 3 ? firstNode.textContent : '').trim();
      if (newOptions.indexOf(val) === -1) chip.remove();
    });
  };

  document.querySelectorAll('.js-chip-select').forEach(function (box) {
    var addBtn = box.querySelector('.chip-add');

    box.querySelectorAll('.chip').forEach(bindRemove);

    if (!addBtn) return;

    addBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      var isOpen = box.classList.contains('open');
      closeOthers();
      if (isOpen) return;

      var options = readOptions(box);
      var remaining = options.filter(function (o) { return currentValues(box).indexOf(o) === -1; });
      var menu = document.createElement('ul');
      menu.className = 'select-menu';
      if (!remaining.length) {
        var empty = document.createElement('li');
        empty.textContent = '選択できる項目がありません';
        empty.style.color = '#9aa4b5';
        empty.style.cursor = 'default';
        menu.appendChild(empty);
      } else {
        remaining.forEach(function (opt) {
          var li = document.createElement('li');
          li.textContent = opt;
          li.addEventListener('click', function (e2) {
            e2.stopPropagation();
            box.insertBefore(makeChip(opt, chipClassFor(box, opt)), addBtn);
            closeMine();
          });
          menu.appendChild(li);
        });
      }
      box.appendChild(menu);
      box.classList.add('open');
    });
  });

  document.addEventListener('click', function () {
    closeOthers();
  });
})();
