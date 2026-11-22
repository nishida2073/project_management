(function () {
  function textOf(v) {
    if (v === undefined || v === null) return '';
    return String(v).trim();
  }

  function dateOf(v) {
    if (typeof v === 'number' && window.XLSX && XLSX.SSF) return XLSX.SSF.format('yyyy/mm/dd', v);
    return textOf(v).replace(/[-.]/g, '/');
  }

  function checkRow(row, spec, rowNo, out) {
    var obj = {};
    for (var i = 0; i < spec.columns.length; i++) {
      var col = spec.columns[i];
      var v = col.type === 'date' ? dateOf(row[col.index]) : textOf(row[col.index]);
      if (!v && col.required) { out.errors.push(rowNo + '行目: ' + col.label + 'がありません'); return null; }
      if (v && col.type === 'date' && !/^\d{4}\/\d{2}\/\d{2}$/.test(v)) { out.errors.push(rowNo + '行目: ' + col.label + 'の形式が不正です（' + v + '）'); return null; }
      if (v && col.type === 'select' && col.options.indexOf(v) === -1) { out.errors.push(rowNo + '行目: ' + col.label + 'が不正です（' + v + '）'); return null; }
      obj[col.key] = col.parse ? col.parse(v) : v;
    }
    return obj;
  }

  function run(file, spec) {
    var reader = new FileReader();
    reader.onload = function (e) {
      var wb = XLSX.read(e.target.result, { type: 'array' });
      var ws = wb.Sheets[wb.SheetNames[0]];
      var aoa = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });
      if (!aoa.length) { MessageDialog.show('ファイルに内容がありません'); return; }
      var head = aoa[0].map(textOf);
      var missingCols = [];
      spec.columns.forEach(function (col) {
        col.index = head.indexOf(col.label);
        if (col.index < 0) missingCols.push(col.label);
      });
      if (missingCols.length) { MessageDialog.show(['ヘッダーに次の列がありません'].concat(missingCols.map(function (c) { return '・' + c; })).join('\n')); return; }

      var out = { errors: [] };
      var existing = spec.existingKeys();
      var fresh = [];
      var updates = [];
      var seen = [];
      for (var r = 1; r < aoa.length; r++) {
        if (aoa[r].every(function (c) { return textOf(c) === ''; })) continue;
        var obj = checkRow(aoa[r], spec, r + 1, out);
        if (!obj) continue;
        var key = spec.keyOf(obj);
        if (key && seen.indexOf(key) !== -1) { out.errors.push((r + 1) + '行目: 同じキーがファイル内にあります（' + key + '）'); continue; }
        seen.push(key);
        if (existing.indexOf(key) !== -1) {
          if (spec.update) updates.push(obj);
        } else {
          fresh.push(obj);
        }
      }
      if (!fresh.length && !updates.length) {
        MessageDialog.show(['取り込める内容がありません'].concat(out.errors).join('\n'));
        return;
      }
      var message = '変更してよろしいですか？';
      if (fresh.length) message += '\n追加：' + fresh.length + '件';
      if (updates.length) message += '\n更新：' + updates.length + '件';
      if (out.errors.length) message += '\n\n取り込まないもの:\n' + out.errors.join('\n');
      MessageDialog.confirm(message).then(function (ok) {
        if (!ok) return;
        fresh.forEach(function (obj) { spec.add(obj); });
        updates.forEach(function (obj) { spec.update(obj); });
        if (spec.refresh) spec.refresh();
      });
    };
    reader.readAsArrayBuffer(file);
  }

  function exportRows(spec, rows, fileName) {
    var head = spec.columns.map(function (col) { return col.label; });
    var body = rows.map(function (row) {
      return spec.columns.map(function (col) {
        if (col.format) return col.format(row);
        return row[col.key] === undefined ? '' : row[col.key];
      });
    });
    var ws = XLSX.utils.aoa_to_sheet([head].concat(body));
    var HEAD = { font: { bold: true, color: { rgb: 'FFFFFF' } }, fill: { patternType: 'solid', fgColor: { rgb: '1C2B45' } }, alignment: { horizontal: 'center', vertical: 'center', wrapText: true }, border: { top: { style: 'thin', color: { rgb: '8A94A6' } }, bottom: { style: 'thin', color: { rgb: '8A94A6' } }, left: { style: 'thin', color: { rgb: '8A94A6' } }, right: { style: 'thin', color: { rgb: '8A94A6' } } } };
    head.forEach(function (_, ci) {
      var addr = XLSX.utils.encode_cell({ r: 0, c: ci });
      if (ws[addr]) ws[addr].s = HEAD;
    });
    ws['!cols'] = head.map(function (name) { return { wch: Math.max(12, String(name).length * 2 + 4) }; });
    var wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, spec.sheetName || 'Sheet1');
    XLSX.writeFile(wb, fileName);
  }

  function bind(spec, ids) {
    var exportBtn = document.getElementById(ids.export);
    var importBtn = document.getElementById(ids.import);
    var input = document.getElementById(ids.file);
    exportBtn.addEventListener('click', function () {
      exportRows(spec, spec.load(), ids.fileName);
    });
    importBtn.addEventListener('click', function () {
      input.value = '';
      input.click();
    });
    input.addEventListener('change', function () {
      var file = input.files && input.files[0];
      if (file) run(file, spec);
    });
  }

  function codeByName(store, name) {
    var t = store.load().filter(function (x) { return x.name === name; })[0];
    return t ? t.code : '';
  }

  function numOf(v) {
    return v === '' || v === undefined ? '' : Number(v);
  }

  window.StoreImport = { run: run, exportRows: exportRows, bind: bind, codeByName: codeByName, numOf: numOf };
})();
