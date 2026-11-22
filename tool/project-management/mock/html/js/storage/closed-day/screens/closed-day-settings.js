(function () {
  var body = $('closedDayBody');
  var editing = null;
  var DATE_RE = /^\d{4}\/\d{2}\/\d{2}$/;
  var TYPES = ['祝日', '休業日'];

  function typeOptions() {
    return TYPES.join(',');
  }

  function viewRow(h) {
    return '<tr data-date="' + esc(h.date) + '">' +
      '<td>' + esc(h.date) + '</td>' +
      '<td>' + esc(h.name) + '</td>' +
      '<td>' + esc(h.type) + '</td>' +
      '<td class="row-actions"><div class="nav-btn cell-action" data-edit>更新</div><div class="btn primary cell-action" data-del>削除</div></td>' +
      '</tr>';
  }

  function editRow(h) {
    var isNew = h === null;
    var date = isNew ? '' : h.date;
    var name = isNew ? '' : h.name;
    var type = isNew ? '' : h.type;
    return '<tr data-date="' + esc(date) + '" data-new="' + (isNew ? '1' : '') + '">' +
      '<td>' + (isNew
        ? '<div class="mini-control js-date" data-f="date"><span class="caret">▾</span></div>'
        : '<div class="mini-control readonly">' + esc(date) + '</div>') + '</td>' +
      '<td><input type="text" class="mini-control cell-input" data-f="name" value="' + esc(name) + '"></td>' +
      '<td><div class="mini-control js-select" data-f="type" data-options="' + esc(typeOptions()) + '">' + esc(type || '選択してください') + '<span class="caret">▾</span></div></td>' +
      '<td class="row-actions"><div class="btn primary cell-action" data-save>保存</div><div class="nav-btn cancel cell-action" data-cancel>キャンセル</div></td>' +
      '</tr>';
  }

  function render() {
    var list = ClosedDayStore.load();
    var rows = list.map(function (h) {
      return editing && editing.date === h.date ? editRow(h) : viewRow(h);
    });
    if (editing && editing.date === null) rows.push(editRow(null));
    body.innerHTML = rows.join('');
    $('closedDayCount').textContent = list.length;
    if (window.bindJsSelect) body.querySelectorAll('.js-select').forEach(function (el) { window.bindJsSelect(el); });
    if (window.bindDatePicker) body.querySelectorAll('.js-date').forEach(function (el) { window.bindDatePicker(el); });
    body.querySelectorAll('tr').forEach(function (tr) {
      var date = tr.getAttribute('data-date');
      var edit = tr.querySelector('[data-edit]');
      if (edit) edit.addEventListener('click', function () { editing = { date: date }; render(); });
      var del = tr.querySelector('[data-del]');
      if (del) del.addEventListener('click', function () {
        MessageDialog.confirm('削除してよろしいですか？').then(function (ok) {
          if (!ok) return;
          ClosedDayStore.remove(date);
          if (editing && editing.date === date) editing = null;
          render();
        });
      });
      var save = tr.querySelector('[data-save]');
      if (save) save.addEventListener('click', function () { saveRow(tr); });
      var cancel = tr.querySelector('[data-cancel]');
      if (cancel) cancel.addEventListener('click', function () { editing = null; render(); });
    });
  }

  function saveRow(tr) {
    var isNew = tr.getAttribute('data-new') === '1';
    var date = isNew ? placeholderToEmpty(ownText(tr.querySelector('[data-f="date"]'))) : tr.getAttribute('data-date');
    var name = tr.querySelector('[data-f="name"]').value.trim();
    var type = placeholderToEmpty(ownText(tr.querySelector('[data-f="type"]')));

    var missing = [];
    if (isNew && !date) missing.push('日付');
    if (!name) missing.push('名称');
    if (!type) missing.push('種別');
    if (missing.length) {
      MessageDialog.required(missing);
      return;
    }
    if (isNew && !DATE_RE.test(date)) {
      MessageDialog.show('日付は「yyyy/mm/dd」の形式で入力してください');
      return;
    }

    if (isNew) {
      if (!ClosedDayStore.add(date, name, type)) {
        MessageDialog.show('同じ日付が既に登録されています');
        return;
      }
    } else {
      var list = ClosedDayStore.load();
      list.forEach(function (h) { if (h.date === date) { h.name = name; h.type = type; } });
      ClosedDayStore.save(list);
    }
    editing = null;
    render();
  }

  $('closedDayAdd').addEventListener('click', function () {
    if (editing && editing.date === null) return;
    editing = { date: null };
    render();
    var newRow = body.querySelector('tr[data-new="1"]');
    if (newRow) newRow.scrollIntoView({ block: 'end' });
  });

  var SHEET_SPEC = {
    sheetName: '休業日',
    load: function () { return ClosedDayStore.load(); },
    columns: [
      { key: 'date', label: '日付', type: 'date', required: true },
      { key: 'name', label: '名称', type: 'text', required: true },
      { key: 'type', label: '種別', type: 'select', options: TYPES, required: true }
    ],
    existingKeys: function () {
      return ClosedDayStore.load().map(function (h) { return h.date; });
    },
    keyOf: function (o) { return o.date; },
    add: function (o) { ClosedDayStore.add(o.date, o.name, o.type); },
    update: function (o) {
      var list = ClosedDayStore.load();
      list.forEach(function (h) { if (h.date === o.date) { h.name = o.name; h.type = o.type; } });
      ClosedDayStore.save(list);
    },
    refresh: render
  };

  StoreImport.bind(SHEET_SPEC, { export: 'closedDayExport', import: 'closedDayImport', file: 'closedDayImportFile', fileName: '休業日.xlsx' });

  render();
})();
