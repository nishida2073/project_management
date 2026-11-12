(function () {
  var btn = document.getElementById('importBtn');
  var input = document.getElementById('importFile');
  if (!btn || !input) return;

  btn.addEventListener('click', function () {
    input.value = '';
    input.click();
  });

  input.addEventListener('change', function () {
    var file = input.files && input.files[0];
    if (!file) return;
    var reader = new FileReader();
    reader.onload = function (e) {
      var wb = XLSX.read(e.target.result, { type: 'array', cellStyles: true });
      var ws = wb.Sheets[wb.SheetNames[0]];
      var aoa = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });
      importRows(aoa, ws);
    };
    reader.readAsArrayBuffer(file);
  });

  function text(v) {
    return String(v === undefined || v === null ? '' : v).trim();
  }

  function lessonText(v) {
    if (typeof v === 'number') return String(v).padStart(3, '0');
    return text(v);
  }

  function mergeUnique(list, add) {
    add.forEach(function (p) {
      var dup = list.some(function (q) { return q.vendor === p.vendor && q.staff === p.staff; });
      if (!dup) list.push(p);
    });
    return list;
  }

  function isColored(cell) {
    if (!cell || !cell.s) return false;
    var pattern = cell.s.patternType || (cell.s.fill && cell.s.fill.patternType);
    var fg = cell.s.fgColor || (cell.s.fill && cell.s.fill.fgColor);
    if (!pattern || pattern === 'none' || !fg || !fg.rgb) return false;
    return String(fg.rgb).toUpperCase().slice(-6) !== 'FFFFFF';
  }

  function importRows(aoa, ws) {
    var vendorName = text(aoa.length ? aoa[0][1] : '');
    var vendorCode = TeacherVenderStore.codeOf(vendorName);
    if (!vendorName || !vendorCode) {
      alert('1行目の講師ベンダー名が見つかりません（' + vendorName + '）');
      return;
    }
    if (!aoa.length) {
      alert('ファイルにデータがありません');
      return;
    }
    var header = (aoa[2] || []).map(text);
    var courseCol = header.indexOf('コース名 / コースコード');
    var lessonCol = header.indexOf('レッスンNo');
    if (courseCol < 0 || lessonCol < 0) {
      alert('登壇依頼書の形式ではありません（コース名 / コースコード、レッスンNo の列が必要です）');
      return;
    }
    var mainCols = [], subCols = [];
    header.forEach(function (h, ci) {
      if (h.indexOf('講師（メイン') === 0) mainCols.push(ci);
      else if (h.indexOf('講師（サブ') === 0) subCols.push(ci);
    });

    var classes = ClassStore.load();
    var updated = 0, skipped = 0, errors = [];

    aoa.slice(3).forEach(function (row, idx) {
      var line = idx + 4;
      var courseCell = text(row[courseCol]);
      if (!courseCell) return;
      var parts = courseCell.split(' / ');
      var courseCode = text(parts[parts.length - 1]);
      var lesson = lessonText(row[lessonCol]);
      var cls = classes.filter(function (c) {
        return c.courseCode === courseCode && c.lessonNo === lesson;
      })[0];
      if (!cls) {
        errors.push(line + '行目: 該当するクラスがありません（' + courseCode + ' ' + lesson + '）');
        return;
      }

      var mains = [], subs = [], rowError = false;
      function collect(cols, target) {
        cols.forEach(function (ci) {
          var name = text(row[ci]);
          if (!name) return;
          if (isColored(ws[XLSX.utils.encode_cell({ r: idx + 3, c: ci })])) return;
          var staff = name;
          if (!staff) {
            rowError = true;
            errors.push(line + '行目: 講師が見つかりません（' + name + '）');
            return;
          }
          target.push({ vendor: vendorCode, staff: staff });
        });
      }
      collect(mainCols, mains);
      collect(subCols, subs);

      if (rowError || (!mains.length && !subs.length)) {
        skipped++;
        return;
      }

      var a = VenderAssignStore.find(cls.id);
      a.mains = mergeUnique(a.mains, mains);
      a.subs = mergeUnique(a.subs, subs);
      VenderAssignStore.upsert(a);
      updated++;
    });

    var msg = '取り込みが完了しました\n更新: ' + updated + '件\n変更なし・スキップ: ' + skipped + '件';
    if (errors.length) {
      msg += '\n\n取り込めなかった内容:\n' + errors.slice(0, 10).join('\n');
      if (errors.length > 10) msg += '\nほか' + (errors.length - 10) + '件';
    }
    alert(msg);
    location.reload();
  }
})();
