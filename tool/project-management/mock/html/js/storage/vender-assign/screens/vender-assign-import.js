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
      var plan = buildPlan(aoa, ws);
      if (plan.error) {
        MessageDialog.show(plan.error);
        return;
      }
      if (!plan.updates.length) {
        MessageDialog.show(['取り込む内容がありません'].concat(plan.errors).join('\n'));
        return;
      }
      sessionStorage.setItem('venderImportPlan', JSON.stringify(serializePlan(plan)));
      location.href = 'vender_assign_import.html';
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

  function isColored(cell) {
    if (!cell || !cell.s) return false;
    var pattern = cell.s.patternType || (cell.s.fill && cell.s.fill.patternType);
    var fg = cell.s.fgColor || (cell.s.fill && cell.s.fill.fgColor);
    if (!pattern || pattern === 'none' || !fg || !fg.rgb) return false;
    return String(fg.rgb).toUpperCase().slice(-6) !== 'FFFFFF';
  }

  function mergeUnique(list, add) {
    add.forEach(function (p) {
      var dup = list.some(function (q) { return q.vendor === p.vendor && q.staff === p.staff; });
      if (!dup) list.push(p);
    });
    return list;
  }

  function uniqueByStaff(list) {
    var seen = {};
    return list.filter(function (p) {
      if (seen[p.staff]) return false;
      seen[p.staff] = true;
      return true;
    });
  }

  function buildPlan(aoa, ws) {
    var vendorName = text(aoa.length ? aoa[0][1] : '');
    var vendorCode = TeacherVenderStore.codeOf(vendorName);
    if (!vendorName || !vendorCode) {
      return { error: '1行目の講師ベンダー名が見つかりません（' + vendorName + '）' };
    }
    var header = (aoa[2] || []).map(text);
    var courseCol = header.indexOf('コースコード');
    var lessonCol = header.indexOf('レッスンNo');
    if (courseCol < 0 || lessonCol < 0) {
      return { error: '登壇依頼の形式ではありません（コースコード、レッスンNo の列が必要です）' };
    }
    var mainCols = [], subCols = [];
    header.forEach(function (h, ci) {
      if (h.indexOf('講師（メイン') === 0) mainCols.push(ci);
      else if (h.indexOf('講師（サブ') === 0) subCols.push(ci);
    });

    var classes = ClassStore.load();
    var plan = { vendorCode: vendorCode, updates: [], skipped: 0, errors: [] };
    aoa.slice(3).forEach(function (row, idx) {
      var line = idx + 4;
      var courseCode = text(row[courseCol]);
      if (!courseCode) return;
      var lesson = lessonText(row[lessonCol]);
      var cls = classes.filter(function (c) {
        return c.courseCode === courseCode && c.lessonNo === lesson;
      })[0];
      if (!cls) {
        plan.errors.push(line + '行目: 該当するクラスがありません（' + courseCode + ' ' + lesson + '）');
        return;
      }

      var mains = [], subs = [];
      function collect(cols, target) {
        cols.forEach(function (ci) {
          if (isColored(ws[XLSX.utils.encode_cell({ r: idx + 3, c: ci })])) return;
          var name = text(row[ci]);
          if (!name) return;
          target.push({ vendor: vendorCode, staff: name });
        });
      }
      collect(mainCols, mains);
      collect(subCols, subs);
      mains = uniqueByStaff(mains);
      subs = uniqueByStaff(subs).filter(function (p) {
        return !mains.some(function (q) { return q.staff === p.staff; });
      });

      if (!mains.length && !subs.length) {
        plan.skipped++;
        return;
      }
      var course = ClassStore.COURSES[cls.courseCode];
      var label = cls.courseCode + '-' + (course ? course.name : cls.courseCode) + '：' + cls.lessonNo;
      plan.updates.push({ cls: cls, mains: mains, subs: subs, label: label });
    });
    return plan;
  }

  function serializePlan(plan) {
    return {
      vendorCode: plan.vendorCode,
      vendorName: TeacherVenderStore.nameOf(plan.vendorCode),
      updates: plan.updates.map(function (u) {
        return {
          classId: u.cls.id,
          year: u.cls.year,
          label: u.label,
          courseCode: u.cls.courseCode,
          courseName: (ClassStore.COURSES[u.cls.courseCode] || {}).name || u.cls.courseCode,
          lessonNo: u.cls.lessonNo,
          start: u.cls.start,
          end: u.cls.end,
          mains: u.mains,
          subs: u.subs
        };
      }),
      skipped: plan.skipped,
      errors: plan.errors
    };
  }
})();
