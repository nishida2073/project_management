(function () {
  var body = $('attrBody');
  var editing = null;

  function targetOf(code) {
    return CustomAttributeStore.TARGETS[code] || '';
  }

  function typeOptions() {
    return Object.keys(CustomAttributeStore.TYPES).map(function (k) { return CustomAttributeStore.TYPES[k]; }).join(',');
  }

  function targetOptions() {
    return Object.keys(CustomAttributeStore.TARGETS).map(function (k) { return CustomAttributeStore.TARGETS[k]; }).join(',');
  }

  function viewRow(a) {
    return '<tr class="cell-row" data-code="' + esc(a.code) + '">' +
      '<td>' + esc(a.name) + '</td>' +
      '<td>' + esc(targetOf(a.target)) + '</td>' +
      '<td>' + esc(CustomAttributeStore.TYPES[a.type] || '') + '</td>' +
      '<td>' + (a.type === 'select' ? esc(a.options.join(', ')) : '-') + '</td>' +
      '<td>' + (a.showInList ? '表示する' : '表示しない') + '</td>' +
      '<td class="row-actions"><div class="nav-btn cell-action" data-edit>更新</div><div class="btn primary cell-action" data-del>削除</div></td>' +
      '</tr>';
  }

  function editRow(a) {
    var isNew = a === null;
    var target = isNew ? '' : targetOf(a.target);
    var type = isNew ? '' : (CustomAttributeStore.TYPES[a.type] || '');
    var name = isNew ? '' : a.name;
    var optionChips = isNew ? '' : a.options.map(function (o) { return chipHtml(o); }).join('');
    var shown = !isNew && a.showInList;
    return '<tr class="cell-row" data-code="' + (isNew ? '' : esc(a.code)) + '" data-new="' + (isNew ? '1' : '') + '" data-type="' + (isNew ? '' : esc(a.type)) + '">' +
      '<td><input type="text" class="mini-control cell-input" data-f="name" value="' + esc(name) + '"></td>' +
      '<td>' + (isNew
        ? '<div class="mini-control js-select" data-f="target" data-options="' + esc(targetOptions()) + '">' + esc(target || '選択してください') + '<span class="caret">▾</span></div>'
        : '<div class="mini-control readonly">' + esc(target) + '</div>') + '</td>' +
      '<td>' + (isNew
        ? '<div class="mini-control js-select" data-f="type" data-options="' + esc(typeOptions()) + '">' + esc(type || '選択してください') + '<span class="caret">▾</span></div>'
        : '<div class="mini-control readonly">' + esc(type) + '</div>') + '</td>' +
      '<td><div class="chip-box cell-chip-box" data-f="options">' + optionChips + '<span class="chip-add">追加</span></div></td>' +
      '<td><div class="toggle-row cell-toggle" data-f="show"><div class="toggle' + (shown ? '' : ' off') + '"><div class="knob"></div></div><div data-label>' + (shown ? '表示する' : '表示しない') + '</div></div></td>' +
      '<td class="row-actions"><div class="btn primary cell-action" data-save>保存</div><div class="nav-btn cancel cell-action" data-cancel>キャンセル</div></td>' +
      '</tr>';
  }

  function chipHtml(value) {
    return '<span class="chip tag-like blue">' + esc(value) + ' </span>';
  }

  function optionValues(box) {
    return Array.prototype.map.call(box.querySelectorAll('.chip'), function (c) { return c.textContent.replace('✕', '').trim(); });
  }

  function addOptionChip(box, value) {
    var chip = document.createElement('span');
    chip.className = 'chip tag-like blue';
    chip.appendChild(document.createTextNode(value + ' '));
    bindChipRemove(chip);
    box.insertBefore(chip, box.querySelector('.chip-add'));
  }

  function bindChipRemove(chip) {
    var x = document.createElement('x');
    x.textContent = '✕';
    x.addEventListener('click', function (e) { e.stopPropagation(); chip.remove(); });
    chip.appendChild(x);
  }

  function bindOptionBox(box, typeEl, tr) {
    var addBtn = box.querySelector('.chip-add');
    box.querySelectorAll('.chip').forEach(function (chip) { bindChipRemove(chip); });
    var sync = function () {
      var isSelect = typeEl ? placeholderToEmpty(ownText(typeEl)) === CustomAttributeStore.TYPES.select : tr.getAttribute('data-type') === 'select';
      addBtn.hidden = !isSelect;
      if (!isSelect) box.querySelectorAll('.chip').forEach(function (chip) { chip.remove(); });
    };
    addBtn.addEventListener('click', function () {
      InputDialog.open({
        title: '選択肢を追加',
        label: '選択肢',
        validate: function (value) {
          if (!value) return '選択肢を入力してください';
          if (optionValues(box).indexOf(value) !== -1) return '同じ選択肢が既に登録されています';
          return '';
        }
      }).then(function (value) {
        if (value) addOptionChip(box, value);
      });
    });
    sync();
    if (typeEl) new MutationObserver(sync).observe(typeEl, { attributes: true, attributeFilter: ['data-value'] });
  }

  function render() {
    var list = CustomAttributeStore.load().filter(function (a) {
      var v = placeholderToEmpty(ownText($('targetFilter')));
      var kw = $('nameFilter').value.trim().toLowerCase();
      return (!v || v === 'すべて' || targetOf(a.target) === v) && (!kw || a.name.toLowerCase().indexOf(kw) !== -1);
    });
    var rows = list.map(function (a) {
      return editing && editing.code === a.code ? editRow(a) : viewRow(a);
    });
    if (editing && editing.code === null) rows.push(editRow(null));
    body.innerHTML = rows.join('');
    $('attrCount').textContent = list.length;
    if (window.bindJsSelect) body.querySelectorAll('.js-select').forEach(function (el) { window.bindJsSelect(el); });
    body.querySelectorAll('tr').forEach(function (tr) {
      var code = tr.getAttribute('data-code');
      var edit = tr.querySelector('[data-edit]');
      if (edit) edit.addEventListener('click', function () { editing = { code: code }; render(); });
      var del = tr.querySelector('[data-del]');
      if (del) del.addEventListener('click', function () {
        MessageDialog.confirm('この項目を削除します。よろしいですか？').then(function (ok) {
          if (!ok) return;
          CustomAttributeStore.remove(code);
          if (editing && editing.code === code) editing = null;
          render();
        });
      });
      var save = tr.querySelector('[data-save]');
      if (save) save.addEventListener('click', function () { saveRow(tr); });
      var cancel = tr.querySelector('[data-cancel]');
      if (cancel) cancel.addEventListener('click', function () { editing = null; render(); });
      var showRow = tr.querySelector('[data-f="show"]');
      if (showRow) {
        var showToggle = showRow.querySelector('.toggle');
        var showLabel = showRow.querySelector('[data-label]');
        showToggle.addEventListener('click', function () {
          var isOn = !showToggle.classList.contains('off');
          showToggle.classList.toggle('off', isOn);
          showLabel.textContent = isOn ? '表示しない' : '表示する';
        });
      }
      var box = tr.querySelector('[data-f="options"]');
      var typeEl = tr.querySelector('[data-f="type"]');
      if (box) bindOptionBox(box, typeEl, tr);
    });
  }

  function saveRow(tr) {
    var name = tr.querySelector('[data-f="name"]').value.trim();
    var options = optionValues(tr.querySelector('[data-f="options"]'));
    var showInList = !tr.querySelector('[data-f="show"] .toggle').classList.contains('off');
    var isNew = tr.getAttribute('data-new') === '1';
    var typeName = isNew ? placeholderToEmpty(ownText(tr.querySelector('[data-f="type"]'))) : '';
    var type = isNew ? (Object.keys(CustomAttributeStore.TYPES).filter(function (k) { return CustomAttributeStore.TYPES[k] === typeName; })[0] || '') : null;
    var targetName = isNew ? placeholderToEmpty(ownText(tr.querySelector('[data-f="target"]'))) : '';
    var code = isNew ? null : tr.getAttribute('data-code');
    var current = isNew ? null : CustomAttributeStore.load().filter(function (x) { return x.code === code; })[0];
    if (!isNew) type = current ? current.type : 'text';

    var missing = [];
    if (isNew && !targetName) missing.push('対象');
    if (!name) missing.push('項目名');
    if (isNew && !type) missing.push('種別');
    if (type === 'select' && !options.length) missing.push('選択肢');
    if (missing.length) {
      MessageDialog.required(missing);
      return;
    }

    var targetKey = isNew ? Object.keys(CustomAttributeStore.TARGETS).filter(function (k) { return CustomAttributeStore.TARGETS[k] === targetName; })[0] : current.target;
    var duplicated = CustomAttributeStore.load().some(function (x) { return x.name === name && x.target === targetKey && x.code !== code; });
    if (duplicated) {
      MessageDialog.show('同じ対象に同じ項目名が既に登録されています');
      return;
    }

    if (isNew) {
      CustomAttributeStore.add({ name: name, target: targetKey, type: type, options: type === 'select' ? options : [], showInList: showInList });
    } else {
      CustomAttributeStore.update(code, { name: name, options: type === 'select' ? options : [], showInList: showInList });
    }
    editing = null;
    render();
  }

  $('attrAdd').addEventListener('click', function () {
    if (editing && editing.code === null) return;
    editing = { code: null };
    render();
    var newRow = body.querySelector('tr[data-new="1"]');
    if (newRow) newRow.scrollIntoView({ block: 'end' });
  });

  $('searchBtn').addEventListener('click', render);
  $('nameFilter').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') $('searchBtn').click();
  });
  render();
})();
