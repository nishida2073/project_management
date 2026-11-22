(function () {
  function render(box, target) {
    CustomAttributeStore.forTarget(target).forEach(function (a) {
      var field = document.createElement('div');
      field.className = 'form-field';
      var label = document.createElement('label');
      label.textContent = a.name;
      field.appendChild(label);
      var control;
      if (a.type === 'select') {
        control = document.createElement('div');
        control.className = 'form-control js-select';
        control.setAttribute('data-options', a.options.join(','));
        control.innerHTML = '選択してください<span class="caret">▾</span>';
        field.appendChild(control);
        if (window.bindJsSelect) window.bindJsSelect(control);
      } else {
        control = document.createElement('input');
        control.type = 'text';
        control.className = 'form-control';
        field.appendChild(control);
      }
      control.setAttribute('data-attr', a.code);
      box.appendChild(field);
    });
  }

  function read(box) {
    var out = {};
    box.querySelectorAll('[data-attr]').forEach(function (el) {
      var v = el.tagName === 'INPUT' ? el.value.trim() : placeholderToEmpty(getSelect(el));
      if (v) out[el.getAttribute('data-attr')] = v;
    });
    return out;
  }

  function fill(box, attrs) {
    box.querySelectorAll('[data-attr]').forEach(function (el) {
      var v = (attrs && attrs[el.getAttribute('data-attr')]) || '';
      if (el.tagName === 'INPUT') el.value = v; else setSelect(el, v);
    });
  }

  function addListColumns(headRow, target) {
    var defs = CustomAttributeStore.forTarget(target).filter(function (a) { return a.showInList; });
    var opTh = headRow.querySelector('.col-actions');
    defs.forEach(function (a) {
      var th = document.createElement('th');
      th.textContent = a.name;
      headRow.insertBefore(th, opTh);
    });
    return defs;
  }

  function listCells(defs, attrs) {
    return defs.map(function (a) { return '<td>' + esc((attrs || {})[a.code] || '-') + '</td>'; }).join('');
  }

  window.CustomAttributeFields = { render: render, read: read, fill: fill, addListColumns: addListColumns, listCells: listCells };
})();
